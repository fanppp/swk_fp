import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { LlmService, TicketTaskExecutionStep } from './MiniLlmService';
import { MiniTaskRequest } from './MiniTaskTypes';
import { UiAutomationRegistry } from './MiniUiAutomationRegistry';
import { MobileGuiStubService } from './MobileGuiStubService';
import { captureFullScreenshot } from './MiniVision';
import { pixelMapToBase64 } from './MiniLlmService';

interface ButtonCenter {
  x: number;
  y: number;
}

interface ScreenBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

interface ButtonCandidate {
  text: string;
  center: ButtonCenter;
  bounds: ScreenBounds;
}

export type TicketLocateStrategy = 'uiTreeFirst' | 'llmFirst';

export class MobileTicketTaskExecutor {
  private static instance: MobileTicketTaskExecutor;

  static getInstance(): MobileTicketTaskExecutor {
    if (!MobileTicketTaskExecutor.instance) {
      MobileTicketTaskExecutor.instance = new MobileTicketTaskExecutor();
    }
    return MobileTicketTaskExecutor.instance;
  }

  async executeRequest(
    context: common.UIAbilityContext,
    request: MiniTaskRequest,
    strategy: TicketLocateStrategy = 'uiTreeFirst'
  ): Promise<string[]> {
    const logs: string[] = [];
    const stubService = MobileGuiStubService.getInstance();
    const llmService = LlmService.getInstance();

    logs.push(`开始执行请求 ${request.requestId}`);
    logs.push(`请求类型: ${request.requestType}`);
    logs.push(`任务时间(打桩执行): ${request.taskTime}`);
    logs.push(`跳转到请求页面: ${request.requestPageUri}`);
    logs.push(`定位策略: ${strategy}`);

    await router.pushUrl({ url: request.requestPageUri });
    await this.sleep(600);

    for (let attempt = 0; attempt < 3; attempt++) {
      const uiTree = UiAutomationRegistry.getInstance().getUiTree() || '';
      logs.push(`第 ${attempt + 1} 次获取UI树，长度=${uiTree.length}`);

      if (strategy === 'uiTreeFirst') {
        const localResult = await this.tryUiTreeFirst(uiTree, logs, stubService);
        if (localResult === 'clicked') {
          return logs;
        }
        if (localResult === 'scrolled') {
          await this.sleep(300);
          continue;
        }
      }

      const screenshotAttachment = await captureFullScreenshot(context);
      const screenshotBase64 = await pixelMapToBase64(screenshotAttachment.pixelMap);
      const plan: TicketTaskExecutionStep = await llmService.planTicketTaskExecutionFromScreen(
        request.requestDescription,
        request.requestPageUri,
        uiTree,
        screenshotBase64
      );
      logs.push(`截图+UI树规划: action=${plan.action}, reason=${plan.reason}`);

      if (plan.action === 'click') {
        const center = this.resolveButtonCenter(uiTree, plan.targetId, plan.targetText);
        if (center) {
          const clickEvent = this.buildClickEvent(center.x, center.y);
          await stubService.imitateClick(clickEvent);
          logs.push(`根据截图理解执行 imitateClick，center=(${center.x}, ${center.y})`);
          return logs;
        }
        logs.push('大模型判断应点击，但UI树中仍未解析出按钮中心点');
      }

      const scrollDown = plan.direction !== 'up';
      const y = scrollDown ? 1750 : 1250;
      await stubService.imitateScrollFromParams(660, y, 660, y, scrollDown ? 'down' : 'up');
      logs.push(`已执行 imitateScroll，direction=${scrollDown ? 'down' : 'up'}`);
      await this.sleep(300);

      if (strategy === 'llmFirst') {
        const localResult = await this.tryUiTreeFirst(UiAutomationRegistry.getInstance().getUiTree() || '', logs, stubService);
        if (localResult === 'clicked') {
          return logs;
        }
      }
    }

    logs.push('执行结束：滑动查找 3 次后仍未找到抢票按钮，查找失败');
    return logs;
  }

  private async tryUiTreeFirst(
    uiTree: string,
    logs: string[],
    stubService: MobileGuiStubService
  ): Promise<'clicked' | 'scrolled' | 'missed'> {
    const visibleButton = this.findVisibleTicketButton(uiTree);
    if (visibleButton) {
      logs.push(`本地UI树已定位按钮: ${visibleButton.text}, center=(${visibleButton.center.x}, ${visibleButton.center.y})`);
      const clickEvent = this.buildClickEvent(visibleButton.center.x, visibleButton.center.y);
      await stubService.imitateClick(clickEvent);
      logs.push(`已执行 imitateClick，center=(${visibleButton.center.x}, ${visibleButton.center.y})`);
      return 'clicked';
    }

    const offscreenButton = this.findTicketButton(uiTree);
    if (offscreenButton) {
      const direction = offscreenButton.center.y < offscreenButton.bounds.top ? 'up' : 'down';
      logs.push(`本地UI树发现目标按钮不在当前屏幕可点击区域，先滚动: ${direction}`);
      const localY = direction === 'down' ? 1750 : 1250;
      await stubService.imitateScrollFromParams(660, localY, 660, localY, direction);
      return 'scrolled';
    }

    logs.push('本地UI树未直接找到抢票按钮');
    return 'missed';
  }

  private resolveButtonCenter(
    uiTree: string,
    targetId?: string,
    targetText?: string
  ): ButtonCenter | undefined {
    const candidate = this.findTicketButton(uiTree, targetId, targetText);
    return candidate ? candidate.center : undefined;
  }

  private findVisibleTicketButton(
    uiTree: string,
    targetId?: string,
    targetText?: string
  ): ButtonCandidate | undefined {
    const candidate = this.findTicketButton(uiTree, targetId, targetText);
    if (!candidate) {
      return undefined;
    }
    const screen = this.parseRootBounds(uiTree);
    if (!screen) {
      return candidate;
    }
    if (candidate.center.x >= screen.left && candidate.center.x <= screen.right &&
      candidate.center.y >= screen.top && candidate.center.y <= screen.bottom) {
      return candidate;
    }
    return undefined;
  }

  private findTicketButton(
    uiTree: string,
    targetId?: string,
    targetText?: string
  ): ButtonCandidate | undefined {
    const lines = uiTree.split('\n');
    const preferredTexts = this.buildTicketTexts(targetText);

    for (const line of lines) {
      const idMatched = targetId ? line.includes(`id: ${targetId}`) : false;
      const textMatched = preferredTexts.some((text: string) => line.includes(`[${text}]`));
      if (!idMatched && !textMatched) {
        continue;
      }

      const boundsMatch = line.match(/bounds\((\d+),(\d+),(\d+),(\d+)\)/);
      if (!boundsMatch) {
        continue;
      }

      const left = Number(boundsMatch[1]);
      const top = Number(boundsMatch[2]);
      const right = Number(boundsMatch[3]);
      const bottom = Number(boundsMatch[4]);
      const center: ButtonCenter = { x: Math.floor((left + right) / 2), y: Math.floor((top + bottom) / 2) };
      const bounds: ScreenBounds = { left, top, right, bottom };
      const resolvedText = preferredTexts.find((text: string) => line.includes(`[${text}]`)) || (targetText || '抢票');
      return { text: resolvedText, center, bounds };
    }

    return undefined;
  }

  private buildTicketTexts(targetText?: string): string[] {
    const values: string[] = [
      targetText || '',
      '抢票',
      '立即抢票',
      '马上抢票',
      '抢这张票',
      '立即抢这张票'
    ].filter((item: string) => item.length > 0);
    return Array.from(new Set(values));
  }

  private parseRootBounds(uiTree: string): ScreenBounds | undefined {
    const match = uiTree.match(/Page .*?bounds\((\d+),(\d+),(\d+),(\d+)\)/);
    if (!match) {
      return undefined;
    }
    return {
      left: Number(match[1]),
      top: Number(match[2]),
      right: Number(match[3]),
      bottom: Number(match[4])
    };
  }

  private buildClickEvent(x: number, y: number): ClickEvent {
    return {
      displayX: x,
      displayY: y,
      windowX: x,
      windowY: y,
      screenX: x,
      screenY: y,
      x,
      y
    } as ClickEvent;
  }

  private async sleep(milliseconds: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, milliseconds));
  }
}
