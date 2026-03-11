import { common } from '@kit.AbilityKit';
import display from '@ohos.display';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CurrentPageMultimodalPlanner } from './mini/CurrentPageMultimodalPlanner';
import { GuiActionPlan, GuiAgentService, GuiSemanticDescriptor, GuiViewport } from './mini/GuiAgentService';
import { ClickMarker, MobileGuiActionLog, MobileGuiStubService } from './mini/MobileGuiStubService';

@Entry
@Component
struct ConcertDetailPage {
  @State userInput: string = '帮我抢票';
  @State logs: MobileGuiActionLog[] = [];
  @State clickMarker?: ClickMarker = undefined;
  @State statusText: string = '等待指令';
  @State perceptionText: string = '尚未采集屏幕语义';

  private readonly stubService: MobileGuiStubService = MobileGuiStubService.getInstance();
  private readonly guiAgent: GuiAgentService = new GuiAgentService();
  private readonly multimodalPlanner: CurrentPageMultimodalPlanner = new CurrentPageMultimodalPlanner();
  private readonly semanticDescriptors: GuiSemanticDescriptor[] = [
    { id: 'concert_title', label: '演唱会详情', role: 'text', clickable: false, keywords: ['演唱会', '详情'] },
    { id: 'instruction_input', label: '指令输入框', role: 'input', clickable: true, keywords: ['输入', '指令'] },
    { id: 'execute_instruction_button', label: '执行指令', role: 'button', clickable: true, keywords: ['执行', '开始'] },
    { id: 'wish_button', label: '想看', role: 'button', clickable: true, keywords: ['收藏', '想看'] },
    { id: 'rush_ticket_button', label: '抢票', role: 'button', clickable: true, keywords: ['抢票', '购票', '买票'] }
  ];
  private viewport: GuiViewport = { width: 1320, height: 2400 };
  private static readonly LOG_DOMAIN: number = 0x0523;
  private static readonly LOG_TAG: string = 'GuiAgentPage';

  aboutToAppear() {
    this.updateViewport();
    this.stubService.clearLogs();
    this.refreshStubState();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 10 }) {
            Text('演唱会详情页')
              .id('concert_title')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor('#111827')
              .alignSelf(ItemAlign.Start);

            Text('最小 GUI 原型：输入“帮我抢票”，当前页会识别可视区域并决定点击或建议滚动。')
              .width('100%')
              .fontSize(14)
              .lineHeight(22)
              .fontColor('#4B5563');
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);

          Column({ space: 12 }) {
            Text('周杰伦 2026 嘉年华世界巡回演唱会')
              .fontSize(22)
              .fontWeight(FontWeight.Medium)
              .fontColor('#0F172A');

            Text('2026.05.23 19:00 周六 | 上海体育场')
              .fontSize(15)
              .fontColor('#475569');

            Text('票档：380 / 680 / 980 / 1380')
              .fontSize(14)
              .fontColor('#475569');
          }
          .width('100%')
          .padding(20)
          .backgroundColor('#FFF7ED')
          .borderRadius(20)
          .alignItems(HorizontalAlign.Start);

          Column({ space: 12 }) {
            Text('Agent 指令')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .alignSelf(ItemAlign.Start);

            TextArea({
              placeholder: '请输入：帮我抢票',
              text: this.userInput
            })
              .id('instruction_input')
              .width('100%')
              .height(960)
              .backgroundColor('#F8FAFC')
              .borderRadius(16)
              .padding(12)
              .onChange((value: string) => {
                this.userInput = value;
              });

            Button('执行指令')
              .id('execute_instruction_button')
              .width('100%')
              .height(48)
              .backgroundColor('#2563EB')
              .fontColor('#FFFFFF')
              .onClick(() => {
                void this.handleUserCommand();
              });
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#EEF2FF')
          .borderRadius(20);

          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Button('想看')
                .id('wish_button')
                .layoutWeight(1)
                .height(44)
                .backgroundColor('#E5E7EB')
                .fontColor('#111827');

              Button('抢票')
                .id('rush_ticket_button')
                .layoutWeight(1)
                .height(44)
                .backgroundColor('#EA580C')
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Medium);
            }
            .width('100%');
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(20);

          Column({ space: 8 }) {
            Text('执行结果')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .alignSelf(ItemAlign.Start);

            Text(`状态：${this.statusText}`)
              .width('100%')
              .fontSize(14)
              .fontColor('#1D4ED8');

            Text(this.perceptionText)
              .width('100%')
              .fontSize(12)
              .lineHeight(18)
              .fontColor('#475569')
              .backgroundColor('#FFFFFF')
              .padding(10)
              .borderRadius(12)
              .maxLines(10);
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#F8FAFC')
          .borderRadius(20)
          .alignItems(HorizontalAlign.Start);

          Column({ space: 8 }) {
            Text('Stub 日志')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .alignSelf(ItemAlign.Start);

            ForEach(this.logs, (item: MobileGuiActionLog) => {
              Text(`[${item.timestamp}] ${item.action} | ${item.params}`)
                .width('100%')
                .fontSize(12)
                .lineHeight(18)
                .fontColor('#475569')
                .padding(10)
                .backgroundColor('#FFFFFF')
                .borderRadius(12);
            }, (item: MobileGuiActionLog) => `${item.timestamp}_${item.action}_${item.params}`);
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#F8FAFC')
          .borderRadius(20)
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 24, bottom: 36 });
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F3F4F6');

      if (this.clickMarker) {
        Column({ space: 4 }) {
          Text(this.clickMarker?.label || '点击目标')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF');

          Text(`(${Math.round(this.clickMarker?.centerX || 0)}, ${Math.round(this.clickMarker?.centerY || 0)})`)
            .fontSize(12)
            .fontColor('#FFFFFF');
        }
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .backgroundColor('#DC2626')
        .borderRadius(14)
        .position({
          x: Math.max(12, (this.clickMarker?.centerX || 0) - ((this.clickMarker?.width || 180) / 2)),
          y: Math.max(12, (this.clickMarker?.centerY || 0) - ((this.clickMarker?.height || 72) / 2))
        });
      }
    }
    .width('100%')
    .height('100%');
  }

  private async handleUserCommand(): Promise<void> {
    const normalizedInput = this.userInput.trim();
    if (!normalizedInput) {
      this.statusText = '请输入指令';
      return;
    }

    const snapshot = this.guiAgent.captureSnapshot(normalizedInput, this.semanticDescriptors, this.viewport);
    const fallbackPlan: GuiActionPlan = this.guiAgent.planAction(snapshot);
    const context = getContext(this) as common.UIAbilityContext;
    const plan: GuiActionPlan = await this.multimodalPlanner.planNextAction(context, snapshot, fallbackPlan);
    this.perceptionText = plan.snapshotText;
    hilog.info(ConcertDetailPage.LOG_DOMAIN, ConcertDetailPage.LOG_TAG, 'suggest %{public}s target=%{public}s reason=%{public}s',
      plan.action, plan.targetLabel || plan.targetId || 'none', plan.reason);

    if (plan.action === 'scroll') {
      this.statusText = plan.reason;
      this.refreshStubState();
      this.showToast(`建议向${plan.direction === 'up' ? '上' : '下'}滚动`);
      return;
    }

    if (plan.action !== 'click' || plan.x === undefined || plan.y === undefined) {
      this.statusText = plan.reason;
      return;
    }

    this.statusText = plan.reason;
    this.stubService.requestFocus(0);
    await this.stubService.imitateClickAt(plan.x, plan.y, `自动点击:${plan.targetLabel || '未知目标'}`);
    this.refreshStubState();
    this.showToast(`已自动点击${plan.targetLabel || '目标按钮'}`);
  }

  private refreshStubState(): void {
    this.logs = this.stubService.getLogs();
    this.clickMarker = this.stubService.getClickMarker();
  }

  private updateViewport(): void {
    try {
      const currentDisplay = display.getDefaultDisplaySync();
      this.viewport = {
        width: Number(currentDisplay.width),
        height: Number(currentDisplay.height)
      };
    } catch (_error) {
      this.viewport = { width: 1320, height: 2400 };
    }
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message,
      duration: 2000
    });
  }
}
