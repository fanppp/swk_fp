import { common } from '@kit.AbilityKit';
import { ClickMarker, MobileGuiActionLog, MobileGuiStubService } from './mini/MobileGuiStubService';
import { MiniTaskRequest } from './mini/MiniTaskTypes';
import { MiniTaskRequestStore } from './mini/MiniTaskRequestStore';
import { MobileTicketTaskExecutor, TicketLocateStrategy } from './mini/MobileTicketTaskExecutor';

interface UiTouchSnapshot {
  type?: number | string;
  action?: number | string;
  screenX?: number;
  screenY?: number;
  windowX?: number;
  windowY?: number;
}

@Entry
@Component
struct MobileGuiTestPage {
  @State inputText: string = '测试抢票';
  @State pastedText: string = '';
  @State longPressHint: string = '请在下方区域真实长按';
  @State scrollHint: string = '请在下方滚动区域真实滑动';
  @State logs: MobileGuiActionLog[] = [];
  @State clickMarker?: ClickMarker = undefined;
  @State latestRequestText: string = '暂无请求任务';
  @State isExecutingTask: boolean = false;
  @State locateStrategy: TicketLocateStrategy = 'screenshotOnly';

  private readonly stubService: MobileGuiStubService = MobileGuiStubService.getInstance();
  private readonly taskStore: MiniTaskRequestStore = MiniTaskRequestStore.getInstance();
  private longPressStartX: number = 0;
  private longPressStartY: number = 0;
  private longPressStartTime: number = 0;

  aboutToAppear() {
    this.stubService.setInputTarget(660, 1590);
    this.refreshTaskRequest();
    this.refreshLogs();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: 16 }) {
        Text('手机端 GUI 测试')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827');

        Text('本页用于手机端直接采集真实点击/触摸参数，再调用 stub 方法执行。执行动作打桩，但参数是真实事件参数。')
          .width('100%')
          .fontSize(14)
          .lineHeight(20)
          .fontColor('#4B5563');

        Column({ space: 10 }) {
          Text('待执行抢票请求')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .alignSelf(ItemAlign.Start);

          Text(this.latestRequestText)
            .width('100%')
            .fontSize(13)
            .lineHeight(20)
            .padding(12)
            .backgroundColor('#FFF7ED')
            .borderRadius(12)
            .fontColor('#7C2D12');

          Button(this.isExecutingTask ? '执行中...' : '执行抢票任务')
            .width('100%')
            .height(46)
            .backgroundColor('#DC2626')
            .enabled(!this.isExecutingTask)
            .onClick(() => {
              void this.executeTicketTask();
            });

          Row() {
            Text('定位策略')
              .fontSize(14)
              .fontColor('#7C2D12');

            Blank()
              .layoutWeight(1);

            Select([
              { value: 'uiTree优先' },
              { value: 'LLM优先' },
              { value: '纯截图' }
            ])
              .selected(this.locateStrategy === 'uiTreeFirst' ? 0 : this.locateStrategy === 'llmFirst' ? 1 : 2)
              .value(
                this.locateStrategy === 'uiTreeFirst' ? 'uiTree优先' :
                this.locateStrategy === 'llmFirst' ? 'LLM优先' : '纯截图'
              )
              .onSelect((index: number) => {
                this.locateStrategy = index === 0 ? 'uiTreeFirst' : index === 1 ? 'llmFirst' : 'screenshotOnly';
              });
          }
          .width('100%');
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFF1F2')
        .borderRadius(16);

        Column({ space: 12 }) {
          Text('点击测试')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .alignSelf(ItemAlign.Start);

          Button('真实点击并调用 imitateClick')
            .width('100%')
            .height(48)
            .backgroundColor('#2563EB')
            .onClick((event: ClickEvent) => {
              void this.handleClick(event);
            });
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#EFF6FF')
        .borderRadius(16);

        Column({ space: 12 }) {
          Text('长按测试')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .alignSelf(ItemAlign.Start);

          Text(this.longPressHint)
            .width('100%')
            .fontSize(13)
            .fontColor('#6B7280');

          Column() {
            Text('长按此区域')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#991B1B');
          }
          .width('100%')
          .height(140)
          .backgroundColor('#FEE2E2')
          .borderRadius(16)
          .justifyContent(FlexAlign.Center)
          .onTouch((event: TouchEvent) => {
            void this.handleLongPressTouch(event);
          });
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFF1F2')
        .borderRadius(16);

        Column({ space: 12 }) {
          Text('滚动测试')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .alignSelf(ItemAlign.Start);

          Text(this.scrollHint)
            .width('100%')
            .fontSize(13)
            .fontColor('#6B7280');

          Scroll() {
            Column({ space: 10 }) {
              ForEach(['第一段内容', '第二段内容', '第三段内容', '第四段内容', '第五段内容', '第六段内容'], (item: string) => {
                Text(item)
                  .width('100%')
                  .padding(12)
                  .backgroundColor('#FFFFFF')
                  .borderRadius(12);
              });
            }
            .width('100%');
          }
          .width('100%')
          .height(180)
          .backgroundColor('#ECFDF5')
          .borderRadius(16)
          .onTouch((event: TouchEvent) => {
            void this.handleScrollTouch(event);
          });
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#F0FDF4')
        .borderRadius(16);

        Column({ space: 12 }) {
          Text('输入测试')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .alignSelf(ItemAlign.Start);

          TextInput({ text: this.inputText, placeholder: '请输入将要写入剪切板的文本' })
            .width('100%')
            .height(44)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.inputText = value;
            });

          TextInput({ text: this.pastedText, placeholder: '目标输入框区域（stub 会点击这里并长按粘贴）' })
            .width('100%')
            .height(44)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .onClick((event: ClickEvent) => {
              this.stubService.requestFocus(0);
              void this.stubService.imitateClick(event).then(() => {
                this.refreshLogs();
              });
            });

          Button('调用 imitateInput')
            .width('100%')
            .height(44)
            .backgroundColor('#7C3AED')
            .onClick(() => {
              void this.handleInput();
            });
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#F5F3FF')
        .borderRadius(16);

        Row({ space: 12 }) {
          Button('刷新日志')
            .layoutWeight(1)
            .height(40)
            .backgroundColor('#334155')
            .onClick(() => {
              this.refreshLogs();
            });

          Button('清空日志')
            .layoutWeight(1)
            .height(40)
            .backgroundColor('#64748B')
            .onClick(() => {
              this.stubService.clearLogs();
              this.refreshLogs();
            });
        }
        .width('100%');

        Column({ space: 8 }) {
          Text('执行日志')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .alignSelf(ItemAlign.Start);

          ForEach(this.logs, (item: MobileGuiActionLog) => {
            Column({ space: 4 }) {
              Text(`[${item.timestamp}] ${item.action}`)
                .width('100%')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#111827');

              Text(item.params)
                .width('100%')
                .fontSize(12)
                .lineHeight(18)
                .fontColor('#4B5563');
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#F8FAFC')
            .borderRadius(12);
          });
        }
        .width('100%');
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 24, bottom: 24 });
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF');

      if (this.clickMarker) {
        Column({ space: 6 }) {
          Text(this.clickMarker?.label || '点击目标区域')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF');

          Text(`(${Math.round(this.clickMarker?.centerX || 0)}, ${Math.round(this.clickMarker?.centerY || 0)})`)
            .fontSize(12)
            .fontColor('#FFFFFF');
        }
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor('#D92D20')
        .borderRadius(14)
        .border({ width: 4, color: '#FEE4E2' })
        .shadow({ radius: 24, color: '#99000000', offsetX: 0, offsetY: 8 })
        .position({
          x: Math.max(8, (this.clickMarker?.centerX || 0) - ((this.clickMarker?.width || 180) / 2)),
          y: Math.max(8, (this.clickMarker?.centerY || 0) - ((this.clickMarker?.height || 72) / 2))
        })
      }
    }
    .width('100%')
    .height('100%');
  }

  private async handleClick(event: ClickEvent): Promise<void> {
    await this.stubService.imitateClick(event);
    this.refreshLogs();
  }

  private async handleLongPressTouch(event: TouchEvent): Promise<void> {
    const touch = event as UiTouchSnapshot;
    const eventType = `${touch.type ?? touch.action ?? ''}`;

    if (eventType === 'Down' || eventType === '1') {
      this.longPressStartX = touch.screenX ?? 0;
      this.longPressStartY = touch.screenY ?? 0;
      this.longPressStartTime = Date.now();
      this.longPressHint = `按下位置: (${this.longPressStartX}, ${this.longPressStartY})`;
      return;
    }

    if ((eventType === 'Up' || eventType === '3') && this.longPressStartTime > 0) {
      const duration = Date.now() - this.longPressStartTime;
      this.longPressHint = `长按结束: (${this.longPressStartX}, ${this.longPressStartY}), ${duration}ms`;
      await this.stubService.imitateLongPress(this.longPressStartX, this.longPressStartY, duration);
      this.refreshLogs();
      this.longPressStartTime = 0;
    }
  }

  private async handleScrollTouch(event: TouchEvent): Promise<void> {
    const touch = event as UiTouchSnapshot;
    const eventType = `${touch.type ?? touch.action ?? ''}`;
    if (eventType !== 'Move' && eventType !== '2') {
      return;
    }
    this.scrollHint = `最近滚动位置: (${touch.screenX ?? 0}, ${touch.screenY ?? 0})`;
    await this.stubService.imitateScroll(event);
    this.refreshLogs();
  }

  private async handleInput(): Promise<void> {
    await this.stubService.imitateInput(this.inputText);
    this.pastedText = this.inputText;
    this.refreshLogs();
  }

  private refreshLogs(): void {
    this.logs = this.stubService.getLogs();
    this.clickMarker = this.stubService.getClickMarker();
  }

  private refreshTaskRequest(): void {
    const request: MiniTaskRequest | undefined = this.taskStore.getLatestRequest();
    if (!request) {
      this.latestRequestText = '暂无请求任务';
      return;
    }

    this.latestRequestText = [
      `RequestId: ${request.requestId}`,
      `Type: ${request.requestType}`,
      `Description: ${request.requestDescription}`,
      `TaskTime: ${request.taskTime}`,
      `PageUri: ${request.requestPageUri}`
    ].join('\n');
  }

  private async executeTicketTask(): Promise<void> {
    const request = this.taskStore.getLatestRequest();
    if (!request) {
      this.scrollHint = '暂无可执行的抢票请求';
      return;
    }

    this.isExecutingTask = true;
    try {
      const executor = MobileTicketTaskExecutor.getInstance();
      const context = getContext(this) as common.UIAbilityContext;
      const executionLogs = await executor.executeRequest(context, request, this.locateStrategy);
      executionLogs.forEach((line: string) => {
        this.stubService.addExternalLog('ticketTask', line);
      });
    } finally {
      this.isExecutingTask = false;
      this.refreshTaskRequest();
      this.refreshLogs();
    }
  }
}
