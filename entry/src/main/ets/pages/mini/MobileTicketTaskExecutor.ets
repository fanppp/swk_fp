import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { LlmService, TicketTaskExecutionStep } from './MiniLlmService';
import { MiniTaskRequest } from './MiniTaskTypes';
import { UiAutomationRegistry } from './MiniUiAutomationRegistry';
import { MobileGuiStubService } from './MobileGuiStubService';
import { captureBottomHalfScreenshot, MiniImageMetadata } from './MiniVision';
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

type CandidateVisibility = 'visible' | 'above' | 'below';

export type TicketLocateStrategy = 'uiTreeFirst' | 'llmFirst' | 'screenshotOnly';

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
    strategy: TicketLocateStrategy = 'screenshotOnly'
  ): Promise<string[]> {
    const logs: string[] = [];
    const stubService = MobileGuiStubService.getInstance();
    const llmService = LlmService.getInstance();

    this.pushLog(logs, `开始执行请求 ${request.requestId}`);
    this.pushLog(logs, `请求类型: ${request.requestType}`);
    this.pushLog(logs, `任务时间(打桩执行): ${request.taskTime}`);
    this.pushLog(logs, `跳转到请求页面: ${request.requestPageUri}`);
    this.pushLog(logs, `定位策略: ${strategy}`);
    this.pushLog(logs, `请求记录的页面滚动位置: ${request.pageScrollOffsetY ?? 0}`);

    await router.pushUrl({ url: request.requestPageUri });
    await this.sleep(1200);

    for (let attempt = 0; attempt < 3; attempt++) {
      const uiTree = UiAutomationRegistry.getInstance().getUiTree() || '';
      this.pushLog(logs, `第 ${attempt + 1} 次获取UI树，长度=${uiTree.length}`);

      if (strategy === 'uiTreeFirst') {
        const localResult = await this.tryUiTreeFirst(uiTree, logs, stubService);
        if (localResult === 'clicked') {
          return logs;
        }
        if (localResult === 'scrolled') {
          await this.sleep(1000);
          continue;
        }
      }

      this.pushLog(logs, '开始截取下半屏并请求大模型进行屏幕理解');
      const screenStart = Date.now();
      const screenshotAttachment = await captureBottomHalfScreenshot(context);
      const screenshotBase64 = await pixelMapToBase64(screenshotAttachment.pixelMap, {
        format: 'image/jpeg',
        quality: 55
      });
      const cropOffsetY = this.extractCropOffsetY(screenshotAttachment.metadata);
      this.pushLog(
        logs,
        `截图完成，耗时=${Date.now() - screenStart}ms，文件=${screenshotAttachment.name}，裁剪=${screenshotAttachment.metadata?.cropRegion || 'unknown'}，offsetY=${cropOffsetY}，编码=jpeg(q=55)`
      );

      let plan = await this.requestScreenPlan(
        llmService,
        request.requestDescription,
        request.requestPageUri,
        screenshotBase64
      );
      if (plan.action === 'click' && !this.hasScreenPoint(plan)) {
        this.pushLog(logs, '第一次截图理解未返回有效坐标，立即重发截图给大模型');
        plan = await this.requestScreenPlan(
          llmService,
          request.requestDescription,
          request.requestPageUri,
          screenshotBase64,
          '上一次返回 click 但没有有效坐标。若当前图中看不到明确按钮，请返回 scroll；若看得到，必须给出按钮中心点坐标。'
        );
      }

      const mappedPlan = this.translatePlanPointFromCrop(plan, cropOffsetY);
      this.pushLog(logs, `截图规划完成，action=${mappedPlan.action}, reason=${mappedPlan.reason}`);

      if (mappedPlan.action === 'click') {
        if (strategy === 'screenshotOnly' && this.hasScreenPoint(mappedPlan)) {
          const clickEvent = this.buildClickEvent(mappedPlan.x as number, mappedPlan.y as number);
          await stubService.imitateClick(clickEvent);
          this.pushLog(logs, `纯截图策略命中目标，直接标记点击区域，center=(${mappedPlan.x}, ${mappedPlan.y})`);
          return logs;
        }

        const candidate = this.findTicketButton(uiTree, mappedPlan.targetId, mappedPlan.targetText);
        if (candidate && this.resolveCandidateVisibility(uiTree, candidate) === 'visible') {
          const clickEvent = this.buildClickEvent(candidate.center.x, candidate.center.y);
          await stubService.imitateClick(clickEvent);
          this.pushLog(logs, `根据截图理解执行 imitateClick，center=(${candidate.center.x}, ${candidate.center.y})`);
          return logs;
        }
        if (this.hasScreenPoint(mappedPlan)) {
          const clickEvent = this.buildClickEvent(mappedPlan.x as number, mappedPlan.y as number);
          await stubService.imitateClick(clickEvent);
          this.pushLog(logs, `UI树未能可靠定位，回退使用截图坐标标记点击区域，center=(${mappedPlan.x}, ${mappedPlan.y})`);
          return logs;
        }
        if (candidate) {
          const direction = this.resolveCandidateVisibility(uiTree, candidate) === 'above' ? 'up' : 'down';
          this.pushLog(logs, `大模型判断应点击，但目标仍在屏幕外，改为先滚动: ${direction}`);
          const y = direction === 'down' ? 1750 : 1250;
          await stubService.imitateScrollFromParams(660, y, 660, y, direction);
          await this.sleep(1000);
          continue;
        }
        this.pushLog(logs, '大模型判断应点击，但未获得可靠坐标，也未从本地UI树解析出按钮中心点');
      }

      const scrollDown = mappedPlan.direction !== 'up';
      const y = scrollDown ? 1750 : 1250;
      await stubService.imitateScrollFromParams(660, y, 660, y, scrollDown ? 'down' : 'up');
      this.pushLog(logs, `已执行 imitateScroll，direction=${scrollDown ? 'down' : 'up'}`);
      await this.sleep(1000);

      if (strategy === 'llmFirst') {
        const localResult = await this.tryUiTreeFirst(UiAutomationRegistry.getInstance().getUiTree() || '', logs, stubService);
        if (localResult === 'clicked') {
          return logs;
        }
      }
    }

    this.pushLog(logs, '执行结束：滑动查找 3 次后仍未找到抢票按钮，查找失败');
    return logs;
  }

  private async tryUiTreeFirst(
    uiTree: string,
    logs: string[],
    stubService: MobileGuiStubService
  ): Promise<'clicked' | 'scrolled' | 'missed'> {
    const visibleButton = this.findVisibleTicketButton(uiTree);
    if (visibleButton) {
      this.pushLog(logs, `本地UI树已定位按钮: ${visibleButton.text}, center=(${visibleButton.center.x}, ${visibleButton.center.y})`);
      const clickEvent = this.buildClickEvent(visibleButton.center.x, visibleButton.center.y);
      await stubService.imitateClick(clickEvent);
      this.pushLog(logs, `已执行 imitateClick，center=(${visibleButton.center.x}, ${visibleButton.center.y})`);
      return 'clicked';
    }

    const offscreenButton = this.findTicketButton(uiTree);
    if (offscreenButton) {
      const direction = this.resolveCandidateVisibility(uiTree, offscreenButton) === 'above' ? 'up' : 'down';
      this.pushLog(logs, `本地UI树发现目标按钮不在当前屏幕可点击区域，先滚动: ${direction}`);
      const localY = direction === 'down' ? 1750 : 1250;
      await stubService.imitateScrollFromParams(660, localY, 660, localY, direction);
      return 'scrolled';
    }

    this.pushLog(logs, '本地UI树未直接找到抢票按钮');
    return 'missed';
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
    if (this.resolveCandidateVisibility(uiTree, candidate) === 'visible') {
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
      const textMatched = this.lineMatchesPreferredText(line, preferredTexts);
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
      const resolvedText = this.extractButtonText(line) || targetText || '抢票';
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
      '立即抢这张票',
      '马上抢这张票',
      '开抢',
      '去抢票'
    ].filter((item: string) => item.length > 0);
    return Array.from(new Set(values));
  }

  private parseRootBounds(uiTree: string): ScreenBounds | undefined {
    const match = uiTree.match(/(?:Page|Window|Scroll|ContentArea) .*?bounds\((\d+),(\d+),(\d+),(\d+)\)/);
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

  private resolveCandidateVisibility(uiTree: string, candidate: ButtonCandidate): CandidateVisibility {
    const screen = this.parseRootBounds(uiTree);
    if (!screen) {
      return 'visible';
    }
    if (candidate.bounds.bottom < screen.top || candidate.center.y < screen.top) {
      return 'above';
    }
    if (candidate.bounds.top > screen.bottom || candidate.center.y > screen.bottom) {
      return 'below';
    }
    return 'visible';
  }

  private lineMatchesPreferredText(line: string, preferredTexts: string[]): boolean {
    const buttonText = this.extractButtonText(line);
    if (!buttonText) {
      return false;
    }
    return preferredTexts.some((text: string) => buttonText.includes(text) || text.includes(buttonText));
  }

  private extractButtonText(line: string): string | undefined {
    const textMatch = line.match(/\[([^\]]+)\]/);
    return textMatch ? textMatch[1] : undefined;
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

  private hasScreenPoint(plan: TicketTaskExecutionStep): boolean {
    return typeof plan.x === 'number' && typeof plan.y === 'number' &&
      Number.isFinite(plan.x) && Number.isFinite(plan.y) &&
      plan.x >= 0 && plan.y >= 0;
  }

  private extractCropOffsetY(metadata?: MiniImageMetadata): number {
    if (!metadata || typeof metadata.cropOffsetY !== 'number' || !Number.isFinite(metadata.cropOffsetY)) {
      return 0;
    }
    return metadata.cropOffsetY;
  }

  private translatePlanPointFromCrop(plan: TicketTaskExecutionStep, cropOffsetY: number): TicketTaskExecutionStep {
    if (!this.hasScreenPoint(plan) || cropOffsetY <= 0) {
      return plan;
    }
    return {
      done: plan.done,
      action: plan.action,
      targetId: plan.targetId,
      targetText: plan.targetText,
      direction: plan.direction,
      x: plan.x,
      y: (plan.y as number) + cropOffsetY,
      reason: plan.reason
    };
  }

  private async requestScreenPlan(
    llmService: LlmService,
    requestDescription: string,
    requestPageUri: string,
    screenshotBase64: string,
    retryHint?: string
  ): Promise<TicketTaskExecutionStep> {
    return llmService.planTicketTaskExecutionFromScreen(
      requestDescription,
      requestPageUri,
      screenshotBase64,
      undefined,
      {
        includeUiTree: false,
        retryHint,
        imageDetail: 'low',
        imageMimeType: 'image/jpeg'
      }
    );
  }

  private pushLog(logs: string[], message: string): void {
    logs.push(`[${this.formatNow()}] ${message}`);
  }

  private formatNow(): string {
    const now = new Date();
    const pad = (value: number, width: number = 2): string => value.toString().padStart(width, '0');
    return `${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}.${pad(now.getMilliseconds(), 3)}`;
  }
}
