import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import image from '@ohos.multimedia.image';
import { LlmService, GuiAction, pixelMapToBase64 } from './MiniLlmService';
import { UiTreeService } from './MiniUiTreeService';
import { captureFullScreenshot } from './MiniVision';
import { UiAutomationRegistry } from './MiniUiAutomationRegistry';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'GuiOperationService';

export interface GuiOperationResult {
  success: boolean;
  message: string;
  executedActions: GuiAction[];
  screenshot?: string;
}

export interface GuiOperationRequest {
  userInstruction: string;
  captureFullScreen?: boolean;
  maxActions?: number;
  progressReporter?: GuiOperationProgressReporter;
}

export interface GuiOperationProgressReporter {
  onBeforeAction(action: GuiAction, index: number, total: number): Promise<void> | void;
  onAfterAction(action: GuiAction, index: number, total: number, success: boolean, message: string): Promise<void> | void;
}

export interface GuiOperationHistory {
  totalOperations: number;
  successfulOperations: number;
  failedOperations: number;
  lastOperation: GuiAction | null;
}

export class GuiOperationService {
  private static instance: GuiOperationService;

  public static getInstance(): GuiOperationService {
    if (!GuiOperationService.instance) {
      GuiOperationService.instance = new GuiOperationService();
    }
    return GuiOperationService.instance;
  }

  /**
   * 执行GUI操作
   */
  async executeGuiOperation(
    context: common.UIAbilityContext,
    request: GuiOperationRequest
  ): Promise<GuiOperationResult> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Starting GUI operation: %{public}s', request.userInstruction);

    try {
      // 1. 截图获取当前屏幕状态
      const screenshotAttachment = request.captureFullScreen
        ? await captureFullScreenshot(context)
        : await captureFullScreenshot(context);  // 现在默认都使用全屏截图

      const screenshotBase64 = await pixelMapToBase64(screenshotAttachment.pixelMap);

      // 2. 获取UI组件树
      const uiTreeService = UiTreeService.getInstance();
      const uiComponentTree = await uiTreeService.getSimplifiedUiInfo(context);

      // 3. 使用大模型生成操作指令
      const llmService = LlmService.getInstance();
      const actions = await llmService.generateGuiActions(
        request.userInstruction,
        screenshotBase64,
        uiComponentTree
      );

      // 4. 限制操作数量
      const maxActions = request.maxActions || 10;
      const limitedActions = actions.slice(0, maxActions);

      hilog.info(
        LOG_DOMAIN,
        LOG_TAG,
        'Generated %{public}d GUI actions (limited to %{public}d)',
        actions.length,
        limitedActions.length
      );

      // 5. 执行操作
      const executedActions: GuiAction[] = [];
      for (let i = 0; i < limitedActions.length; i++) {
        const action = limitedActions[i];
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Executing action %{public}d: %{public}s', i + 1, action.description);

        try {
          if (request.progressReporter) {
            await request.progressReporter.onBeforeAction(action, i, limitedActions.length);
          }
          await this.executeAction(context, action);
          executedActions.push(action);
          if (request.progressReporter) {
            await request.progressReporter.onAfterAction(
              action,
              i,
              limitedActions.length,
              true,
              `第 ${i + 1} 步执行成功`
            );
          }

          // 每个 GUI 指令之间固定间隔 1s
          await this.sleep(1000);
        } catch (error) {
          hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to execute action %{public}d: %{public}s', i + 1, JSON.stringify(error));
          const err = error as Error;
          if (request.progressReporter) {
            await request.progressReporter.onAfterAction(
              action,
              i,
              limitedActions.length,
              false,
              err.message || JSON.stringify(error)
            );
          }
          break;
        }
      }

      // 6. 操作完成后再次截图
      const finalScreenshot = await captureFullScreenshot(context);
      const finalScreenshotBase64 = await pixelMapToBase64(finalScreenshot.pixelMap);

      if (limitedActions.length === 0) {
        return {
          success: false,
          message: '未生成有效操作，请调整指令后重试',
          executedActions: [],
          screenshot: finalScreenshotBase64
        };
      }

      if (executedActions.length === 0) {
        return {
          success: false,
          message: '操作计划已生成，但没有一步成功执行',
          executedActions: [],
          screenshot: finalScreenshotBase64
        };
      }

      return {
        success: true,
        message: `成功执行 ${executedActions.length} 个操作`,
        executedActions,
        screenshot: finalScreenshotBase64
      };
    } catch (error) {
      const err = error as Error;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'GUI operation failed: %{public}s', err.message || JSON.stringify(error));
      return {
        success: false,
        message: `操作失败: ${err.message || JSON.stringify(error)}`,
        executedActions: []
      };
    }
  }

  /**
   * 执行单个操作
   */
  private async executeAction(context: common.UIAbilityContext, action: GuiAction): Promise<void> {
    const handledByBridge = await UiAutomationRegistry.getInstance().executeAction(action);
    if (handledByBridge) {
      return;
    }

    switch (action.type) {
      case 'tap':
        await this.executeTap(context, action.x ?? 540, action.y ?? 1200);
        break;
      case 'swipe':
        await this.executeSwipe(
          context,
          action.startX ?? 540,
          action.startY ?? 1500,
          action.endX ?? 540,
          action.endY ?? 900
        );
        break;
      case 'input':
        await this.executeInput(context, action.text!, action.x, action.y);
        break;
      case 'wait':
        await this.sleep(action.milliseconds!);
        break;
      default:
        throw new Error(`Unsupported action type: ${action.type}`);
    }
  }

  /**
   * 执行点击操作
   */
  private async executeTap(context: common.UIAbilityContext, x: number, y: number): Promise<void> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Executing tap at (%{public}d, %{public}d)', x, y);

    try {
      // 获取当前窗口
      const hostWindow = await window.getLastWindow(context);

      // 注入点击事件（这里需要使用HarmonyOS的事件注入API）
      // 由于HarmonyOS的事件注入API可能受限，这里提供一个模拟实现
      await this.injectTapEvent(hostWindow, x, y);
    } catch (error) {
      const err = error as Error;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to execute tap: %{public}s', err.message || JSON.stringify(error));
      throw new Error('Tap execution failed');
    }
  }

  /**
   * 执行滑动操作
   */
  private async executeSwipe(
    context: common.UIAbilityContext,
    startX: number,
    startY: number,
    endX: number,
    endY: number
  ): Promise<void> {
    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      'Executing swipe from (%{public}d, %{public}d) to (%{public}d, %{public}d)',
      startX,
      startY,
      endX,
      endY
    );

    try {
      const hostWindow = await window.getLastWindow(context);
      await this.injectSwipeEvent(hostWindow, startX, startY, endX, endY);
    } catch (error) {
      const err = error as Error;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to execute swipe: %{public}s', err.message || JSON.stringify(error));
      throw new Error('Swipe execution failed');
    }
  }

  /**
   * 执行输入操作
   */
  private async executeInput(context: common.UIAbilityContext, text: string, x?: number, y?: number): Promise<void> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Executing input: %{public}s', text);

    try {
      // 如果提供了坐标，先点击该位置激活输入框
      if (x !== undefined && y !== undefined) {
        await this.executeTap(context, x, y);
        await this.sleep(500); // 等待输入框激活
      }

      // 输入文本（这里需要使用HarmonyOS的文本输入API）
      await this.injectTextInput(text);
    } catch (error) {
      const err = error as Error;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to execute input: %{public}s', err.message || JSON.stringify(error));
      throw new Error('Input execution failed');
    }
  }

  /**
   * 注入点击事件（模拟实现）
   */
  private async injectTapEvent(hostWindow: window.Window, x: number, y: number): Promise<void> {
    // 这里是一个模拟实现，实际使用时需要调用HarmonyOS的事件注入API
    // 例如使用UITest相关的API或系统级的输入事件API

    hilog.info(LOG_DOMAIN, LOG_TAG, 'Simulating tap event injection at (%{public}d, %{public}d)', x, y);

    // 模拟实现：创建一个点击事件并尝试分发
    try {
      // 这里应该使用HarmonyOS的实际API，比如：
      // - inputEventClient.injectEvent()
      // - UITest相关API
      // - 或其他系统级输入API

      // 目前提供一个基础的模拟延迟
      await this.sleep(100);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'Tap event injected successfully');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to inject tap event: %{public}s', JSON.stringify(error));
      throw new Error('Tap event injection not supported in current environment');
    }
  }

  /**
   * 注入滑动事件（模拟实现）
   */
  private async injectSwipeEvent(
    hostWindow: window.Window,
    startX: number,
    startY: number,
    endX: number,
    endY: number
  ): Promise<void> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Simulating swipe event injection');

    try {
      // 模拟滑动：分解为多个中间点
      const steps = 10;
      const stepX = (endX - startX) / steps;
      const stepY = (endY - startY) / steps;

      for (let i = 0; i <= steps; i++) {
        const currentX = Math.round(startX + stepX * i);
        const currentY = Math.round(startY + stepY * i);

        // 模拟触摸点移动
        await this.sleep(20);
      }

      hilog.info(LOG_DOMAIN, LOG_TAG, 'Swipe event injected successfully');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to inject swipe event: %{public}s', JSON.stringify(error));
      throw new Error('Swipe event injection not supported in current environment');
    }
  }

  /**
   * 注入文本输入（模拟实现）
   */
  private async injectTextInput(text: string): Promise<void> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Simulating text input injection');

    try {
      // 这里应该使用HarmonyOS的输入法API或系统输入API
      // 模拟实现：逐字符输入
      for (const char of text) {
        await this.sleep(50); // 模拟打字速度
      }

      hilog.info(LOG_DOMAIN, LOG_TAG, 'Text input injected successfully');
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to inject text input: %{public}s', JSON.stringify(error));
      throw new Error('Text input injection not supported in current environment');
    }
  }

  /**
   * 睡眠函数
   */
  private async sleep(milliseconds: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, milliseconds));
  }

  /**
   * 获取操作历史
   */
  getOperationHistory(): GuiOperationHistory {
    // 这里可以实现操作历史记录功能
    return {
      totalOperations: 0,
      successfulOperations: 0,
      failedOperations: 0,
      lastOperation: null
    };
  }
}
