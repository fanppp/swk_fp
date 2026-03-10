import { GuiAction } from './MiniLlmService';

export interface UiAutomationBridge {
  pageName: string;
  getUiTree(): string;
  executeAction(action: GuiAction): Promise<boolean>;
}

export class RegisteredUiAutomationBridge implements UiAutomationBridge {
  pageName: string;
  private readonly treeGetter: () => string;
  private readonly actionExecutor: (action: GuiAction) => Promise<boolean>;

  constructor(
    pageName: string,
    treeGetter: () => string,
    actionExecutor: (action: GuiAction) => Promise<boolean>
  ) {
    this.pageName = pageName;
    this.treeGetter = treeGetter;
    this.actionExecutor = actionExecutor;
  }

  getUiTree(): string {
    return this.treeGetter();
  }

  executeAction(action: GuiAction): Promise<boolean> {
    return this.actionExecutor(action);
  }
}

export class UiAutomationRegistry {
  private static instance: UiAutomationRegistry;
  private bridge?: UiAutomationBridge;

  public static getInstance(): UiAutomationRegistry {
    if (!UiAutomationRegistry.instance) {
      UiAutomationRegistry.instance = new UiAutomationRegistry();
    }
    return UiAutomationRegistry.instance;
  }

  registerBridge(bridge: UiAutomationBridge): void {
    this.bridge = bridge;
  }

  unregisterBridge(pageName: string): void {
    if (this.bridge && this.bridge.pageName === pageName) {
      this.bridge = undefined;
    }
  }

  getUiTree(): string | undefined {
    return this.bridge?.getUiTree();
  }

  async executeAction(action: GuiAction): Promise<boolean> {
    if (!this.bridge) {
      return false;
    }
    return this.bridge.executeAction(action);
  }
}
