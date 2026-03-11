import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'MobileGuiStub';
const EXEC_LOG_TAG: string = 'GuiAgentExec';

export interface MobileGuiActionLog {
  timestamp: string;
  action: string;
  params: string;
}

export interface ClickMarker {
  centerX: number;
  centerY: number;
  width: number;
  height: number;
  label: string;
  createdAt: number;
}

export class MobileGuiStubService {
  private static instance: MobileGuiStubService;
  private logs: MobileGuiActionLog[] = [];
  private clickMarker?: ClickMarker = undefined;

  static getInstance(): MobileGuiStubService {
    if (!MobileGuiStubService.instance) {
      MobileGuiStubService.instance = new MobileGuiStubService();
    }
    return MobileGuiStubService.instance;
  }

  requestFocus(targetWindowId: number): boolean {
    this.appendLog('requestFocus', `targetWindowId=${targetWindowId}`);
    return true;
  }

  async imitateClickAt(x: number, y: number, label: string = '点击目标区域'): Promise<void> {
    this.setClickMarker(x, y, label);
    this.appendLog('imitateClickAt', `x=${x}, y=${y}, label=${label}`);
    await this.sleep(120);
  }

  getLogs(): MobileGuiActionLog[] {
    return [...this.logs].reverse();
  }

  getClickMarker(): ClickMarker | undefined {
    return this.clickMarker;
  }

  clearLogs(): void {
    this.logs = [];
    this.clickMarker = undefined;
  }

  private setClickMarker(x: number, y: number, label: string): void {
    this.clickMarker = {
      centerX: x,
      centerY: y,
      width: 180,
      height: 72,
      label,
      createdAt: Date.now()
    };
  }

  private appendLog(action: string, params: string): void {
    const timestamp = new Date().toLocaleTimeString();
    this.logs.push({ timestamp, action, params });
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s | %{public}s', action, params);
    hilog.info(LOG_DOMAIN, EXEC_LOG_TAG, 'exec %{public}s %{public}s', action, params);
  }

  private async sleep(milliseconds: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, milliseconds));
  }
}
