import { hilog } from '@kit.PerformanceAnalysisKit';
import pasteboard from '@ohos.pasteboard';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'MobileGuiStub';

export interface MobileGuiActionLog {
  timestamp: string;
  action: string;
  params: string;
}

interface UiTouchSnapshot {
  type?: number | string;
  action?: number | string;
  source?: number | string;
  screenX?: number;
  screenY?: number;
  windowX?: number;
  windowY?: number;
  displayX?: number;
  displayY?: number;
  touches?: Object[];
}

interface UiClickSnapshot {
  displayX?: number;
  displayY?: number;
  windowX?: number;
  windowY?: number;
  screenX?: number;
  screenY?: number;
  x?: number;
  y?: number;
  timestamp?: number;
  source?: number | string;
}

export class MobileGuiStubService {
  private static instance: MobileGuiStubService;
  private logs: MobileGuiActionLog[] = [];
  private inputTargetX: number = 660;
  private inputTargetY: number = 1580;

  static getInstance(): MobileGuiStubService {
    if (!MobileGuiStubService.instance) {
      MobileGuiStubService.instance = new MobileGuiStubService();
    }
    return MobileGuiStubService.instance;
  }

  setInputTarget(x: number, y: number): void {
    this.inputTargetX = x;
    this.inputTargetY = y;
    this.appendLog('setInputTarget', `x=${x}, y=${y}`);
  }

  requestFocus(targetWindowId: number): boolean {
    this.appendLog('requestFocus', `targetWindowId=${targetWindowId}`);
    return true;
  }

  async imitateClick(event: ClickEvent): Promise<void> {
    const params = this.stringifyClickEvent(event);
    this.appendLog('imitateClick', params);
    await this.sleep(120);
  }

  async imitateLongPress(x: number, y: number, milliseconds: number): Promise<void> {
    this.appendLog('imitateLongPress', `x=${x}, y=${y}, milliseconds=${milliseconds}`);
    await this.sleep(160);
  }

  async imitateScroll(event: TouchEvent): Promise<void> {
    const touchEvent = event as UiTouchSnapshot;
    const params = [
      `type=${touchEvent.type ?? 'unknown'}`,
      `action=${touchEvent.action ?? 'unknown'}`,
      `screenX=${touchEvent.screenX ?? 'unknown'}`,
      `screenY=${touchEvent.screenY ?? 'unknown'}`,
      `windowX=${touchEvent.windowX ?? 'unknown'}`,
      `windowY=${touchEvent.windowY ?? 'unknown'}`,
      `touches=${touchEvent.touches ? touchEvent.touches.length : 0}`
    ].join(', ');
    this.appendLog('imitateScroll', params);
    await this.sleep(120);
  }

  async imitateScrollFromParams(
    screenX: number,
    screenY: number,
    windowX: number,
    windowY: number,
    direction: string
  ): Promise<void> {
    const params = [
      'type=Move',
      'action=2',
      `screenX=${screenX}`,
      `screenY=${screenY}`,
      `windowX=${windowX}`,
      `windowY=${windowY}`,
      `direction=${direction}`
    ].join(', ');
    this.appendLog('imitateScroll', params);
    await this.sleep(120);
  }

  async imitateInput(text: string): Promise<void> {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    await pasteboard.getSystemPasteboard().setData(pasteData);
    this.appendLog('imitateInput', `text=${text}, inputTargetX=${this.inputTargetX}, inputTargetY=${this.inputTargetY}`);
    this.appendLog('imitateInput.copy', `clipboard=text/plain:${text}`);
    this.appendLog('imitateInput.clickInputArea', `x=${this.inputTargetX}, y=${this.inputTargetY}`);
    this.appendLog('imitateInput.longPressInputArea', `x=${this.inputTargetX}, y=${this.inputTargetY}, milliseconds=800`);
    this.appendLog('imitateInput.paste', 'operation=paste');
    await this.sleep(160);
  }

  getLogs(): MobileGuiActionLog[] {
    return [...this.logs].reverse();
  }

  clearLogs(): void {
    this.logs = [];
  }

  addExternalLog(action: string, params: string): void {
    this.appendLog(action, params);
  }

  private appendLog(action: string, params: string): void {
    const timestamp = new Date().toLocaleTimeString();
    this.logs.push({ timestamp, action, params });
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s | %{public}s', action, params);
  }

  private stringifyClickEvent(event: ClickEvent): string {
    const candidate = event as UiClickSnapshot;
    const parts: string[] = [];
    if (candidate.displayX !== undefined) {
      parts.push(`displayX=${candidate.displayX}`);
    }
    if (candidate.displayY !== undefined) {
      parts.push(`displayY=${candidate.displayY}`);
    }
    if (candidate.windowX !== undefined) {
      parts.push(`windowX=${candidate.windowX}`);
    }
    if (candidate.windowY !== undefined) {
      parts.push(`windowY=${candidate.windowY}`);
    }
    if (candidate.screenX !== undefined) {
      parts.push(`screenX=${candidate.screenX}`);
    }
    if (candidate.screenY !== undefined) {
      parts.push(`screenY=${candidate.screenY}`);
    }
    if (candidate.x !== undefined) {
      parts.push(`x=${candidate.x}`);
    }
    if (candidate.y !== undefined) {
      parts.push(`y=${candidate.y}`);
    }
    if (candidate.timestamp !== undefined) {
      parts.push(`timestamp=${candidate.timestamp}`);
    }
    if (candidate.source !== undefined) {
      parts.push(`source=${candidate.source}`);
    }

    return parts.length > 0 ? parts.join(', ') : '[ClickEvent captured]';
  }

  private async sleep(milliseconds: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, milliseconds));
  }
}
