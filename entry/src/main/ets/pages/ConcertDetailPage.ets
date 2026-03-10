import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { captureFullScreenshot, saveScreenshotToGallery } from './mini/MiniVision';
import { identifyTaskFromUserInput, EnhancedTaskResult } from './mini/MiniLlm';
import { buildTaskFromParsedInfo, MiniTaskBuildInput } from './mini/MiniTaskBuilder';
import { MiniTaskCardData, MiniTaskRequest } from './mini/MiniTaskTypes';
import { RegisteredUiAutomationBridge, UiAutomationRegistry } from './mini/MiniUiAutomationRegistry';
import { GuiAction } from './mini/MiniLlmService';
import { MiniTaskRequestStore } from './mini/MiniTaskRequestStore';

interface CountdownTime {
  days: number;
  hours: number;
  minutes: number;
  seconds: number;
}

@Entry
@Component
struct ConcertDetailPage {
  @State countdown: CountdownTime = { days: 0, hours: 6, minutes: 29, seconds: 15 };
  @State isLiked: boolean = false;
  @State userInput: string = '等下帮我抢这张演唱会门票';
  @State isProcessing: boolean = false;
  @State resultText: string = '';
  @State logText: string = '';
  private timer?: number = undefined;

  aboutToAppear() {
    this.startCountdown();
    const bridge = new RegisteredUiAutomationBridge(
      'ConcertDetailPage',
      (): string => this.buildConcertUiTree(),
      async (_action: GuiAction): Promise<boolean> => false
    );
    UiAutomationRegistry.getInstance().registerBridge(bridge);
  }

  aboutToDisappear() {
    if (this.timer) {
      clearInterval(this.timer);
    }
    UiAutomationRegistry.getInstance().unregisterBridge('ConcertDetailPage');
  }

  build() {
    Scroll() {
      Column() {
        // 顶部演唱会信息
        Row() {
          Text('***演唱会')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1E1E1E')
            .margin({ left: 16, top: 20 });
        }
        .width('100%')
        .justifyContent(FlexAlign.Start);

        Blank()
          .height(220);

        // 中间时间信息
        Column({ space: 8 }) {
          Text('2026.05.23 19:00 周六')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333');

          Text('演出时间')
            .fontSize(14)
            .fontColor('#666666');
        }
        .margin({ top: 40, bottom: 40 });

        Blank()
          .height(260);

        // 底部操作区域
        Column({ space: 16 }) {
          Column({ space: 8 }) {
            Text('页面说明')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .alignSelf(ItemAlign.Start);

            Text('向上滑动可查看识别日志、相册保存结果以及大模型返回的结构化任务信息。')
              .fontSize(13)
              .lineHeight(18)
              .fontColor('#666666');
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFF7ED')
          .borderRadius(12);

          // 抢票识别测试区域
          Column({ space: 12 }) {
            Text('抢票识别测试')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .alignSelf(ItemAlign.Start);

            TextArea({
              placeholder: '请输入抢票指令，如：等下帮我抢这张演唱会门票',
              text: this.userInput
            })
              .width('100%')
              .height(60)
              .backgroundColor('#F8F8F8')
              .borderRadius(8)
              .padding(8)
              .onChange((value: string) => {
                this.userInput = value;
              });

            Button(this.isProcessing ? '识别中...' : '智能识别抢票任务')
              .width('100%')
              .height(44)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .backgroundColor('#4CAF50')
              .borderRadius(8)
              .enabled(!this.isProcessing && this.userInput.trim().length > 0)
              .onClick(() => {
                void this.processTicketRequest();
              });
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#F9F9F9')
          .borderRadius(12);

          Text(`3月10日 15:00开抢，仅${this.formatCountdown()}`)
            .fontSize(14)
            .fontColor('#FF6B35')
            .fontWeight(FontWeight.Medium);

          Row({ space: 12 }) {
            Row({ space: 6 }) {
              Text('♥')
                .fontSize(16)
                .fontColor(this.isLiked ? '#FF6B35' : '#999999');

              Text('想看')
                .fontSize(14)
                .fontColor('#666666');
            }
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(20)
            .border({ width: 1, color: '#E0E0E0' })
            .onClick(() => {
              this.isLiked = !this.isLiked;
            });

            Blank()
              .layoutWeight(1);

            Button('抢票')
              .width(100)
              .height(40)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .backgroundColor('#FF6B35')
              .borderRadius(20)
              .onClick(() => {
                this.goToTicketService();
              });
          }
          .width('100%')
          .padding({ left: 16, right: 16 });

          if (this.resultText || this.logText) {
            Column({ space: 8 }) {
              if (this.logText) {
                Text('处理日志')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .alignSelf(ItemAlign.Start);

                Text(this.logText)
                  .width('100%')
                  .fontSize(12)
                  .lineHeight(16)
                  .fontColor('#666666')
                  .backgroundColor('#F0F0F0')
                  .padding(8)
                  .borderRadius(6);
              }

              if (this.resultText) {
                Text('识别结果')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .alignSelf(ItemAlign.Start);

                Text(this.resultText)
                  .width('100%')
                  .fontSize(12)
                  .lineHeight(16)
                  .fontColor('#333333')
                  .backgroundColor('#E8F5E8')
                  .padding(12)
                  .borderRadius(8);
              }
            }
            .width('100%')
            .padding(16)
            .alignItems(HorizontalAlign.Start);
          }
        }
        .margin({ bottom: 40 })
        .padding({ left: 16, right: 16 });
      }
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF');
  }

  /**
   * 启动倒计时
   */
  private startCountdown() {
    this.timer = setInterval(() => {
      if (this.countdown.seconds > 0) {
        this.countdown.seconds--;
      } else if (this.countdown.minutes > 0) {
        this.countdown.minutes--;
        this.countdown.seconds = 59;
      } else if (this.countdown.hours > 0) {
        this.countdown.hours--;
        this.countdown.minutes = 59;
        this.countdown.seconds = 59;
      } else if (this.countdown.days > 0) {
        this.countdown.days--;
        this.countdown.hours = 23;
        this.countdown.minutes = 59;
        this.countdown.seconds = 59;
      } else {
        // 倒计时结束
        if (this.timer) {
          clearInterval(this.timer);
        }
      }

      // 触发UI更新
      this.countdown = {
        days: this.countdown.days,
        hours: this.countdown.hours,
        minutes: this.countdown.minutes,
        seconds: this.countdown.seconds
      };
    }, 1000);
  }

  /**
   * 格式化倒计时显示
   */
  private formatCountdown(): string {
    const pad = (num: number) => num.toString().padStart(2, '0');

    if (this.countdown.days > 0) {
      return `${this.countdown.days}天${pad(this.countdown.hours)}时${pad(this.countdown.minutes)}分${pad(this.countdown.seconds)}秒`;
    } else {
      return `${pad(this.countdown.hours)}时${pad(this.countdown.minutes)}分${pad(this.countdown.seconds)}秒`;
    }
  }

  /**
   * 处理抢票请求
   */
  private async processTicketRequest(): Promise<void> {
    if (this.isProcessing || !this.userInput.trim()) {
      return;
    }

    this.isProcessing = true;
    this.resultText = '';
    this.logText = '';
    this.appendLog('🚀 开始处理抢票请求...');

    try {
      const context = getContext(this) as common.UIAbilityContext;

      // 1. 截图
      this.appendLog('📸 正在截取当前页面...');
      const screenshotAttachment = await captureFullScreenshot(context);
      this.appendLog(`✅ 截图完成: ${screenshotAttachment.name}`);

      // 2. 保存截图到图库
      try {
        const galleryUri = await saveScreenshotToGallery(context, screenshotAttachment.pixelMap);
        this.appendLog(`💾 截图已保存到图库: ${galleryUri}`);
      } catch (error) {
        this.appendLog(`⚠️ 保存到图库失败，但继续处理...`);
      }

      // 3. 使用大模型进行智能识别
      this.appendLog('🤖 正在使用大模型分析任务...');
      this.appendLog('📊 分析内容包括: 截图 + UI组件树 + 用户指令');
      this.appendLog(`🧩 当前UI树摘要已注入，长度: ${this.buildConcertUiTree().length}`);

      const taskResult: EnhancedTaskResult = await identifyTaskFromUserInput(
        context,
        this.userInput,
        screenshotAttachment.pixelMap
      );

      this.appendLog('✨ 大模型分析完成！');
      this.appendLog(`🎯 任务类型: ${taskResult.taskType}`);
      this.appendLog(`📋 任务标题: ${taskResult.title}`);
      this.appendLog(`⏰ 时间信息: ${taskResult.timeText || '未识别到时间'}`);
      this.appendLog(`🔍 置信度: ${(taskResult.confidence * 100).toFixed(1)}%`);

      // 4. 构建任务对象
      const taskInput: MiniTaskBuildInput = {
        taskType: taskResult.taskType,
        title: taskResult.title,
        timeText: taskResult.timeText,
        scheduleType: 'once',
        extraInfo: taskResult.extraInfo
      };

      const task: MiniTaskCardData = buildTaskFromParsedInfo(this.userInput, taskInput);
      const request: MiniTaskRequest = {
        requestId: `REQ_${Date.now()}`,
        requestType: taskResult.taskType,
        requestDescription: this.userInput,
        taskTime: taskResult.timeText || '立即执行(打桩)',
        requestPageUri: 'pages/ConcertDetailPage',
        title: taskResult.title,
        createdAt: Date.now()
      };
      MiniTaskRequestStore.getInstance().saveRequest(request);
      this.appendLog(`🗂️ 已生成任务请求: ${request.requestId}`);
      this.appendLog(`🔗 请求页面URI: ${request.requestPageUri}`);

      // 5. 格式化显示结果
      this.resultText = this.formatTaskResult(taskResult, task, request);
      this.appendLog('🎉 抢票任务识别完成！');

      this.showToast(`识别成功: ${taskResult.title} (${(taskResult.confidence * 100).toFixed(0)}%)`);

    } catch (error) {
      const err = error as Error;
      this.appendLog(`❌ 处理失败: ${err.message || JSON.stringify(error)}`);
      this.showToast('抢票识别失败，请重试');
    } finally {
      this.isProcessing = false;
    }
  }

  /**
   * 格式化任务结果
   */
  private formatTaskResult(result: EnhancedTaskResult, task: MiniTaskCardData, request: MiniTaskRequest): string {
    const lines: string[] = [];
    lines.push('🎫 === 抢票任务识别结果 === 🎫');
    lines.push('');
    lines.push(`📋 任务类型: ${result.taskType}`);
    lines.push(`🎭 任务标题: ${result.title}`);
    lines.push(`⏰ 执行时间: ${result.timeText || '待确定'}`);
    lines.push(`🎯 识别置信度: ${(result.confidence * 100).toFixed(1)}%`);
    lines.push('');

    if (result.extraInfo) {
      lines.push(`ℹ️ 额外信息: ${result.extraInfo}`);
      lines.push('');
    }

    lines.push('📊 === 生成的任务详情 === 📊');
    lines.push(`🆔 任务ID: ${task.id}`);
    lines.push(`📝 描述: ${task.description}`);
    lines.push(`📅 创建时间: ${new Date(task.createdAt).toLocaleString()}`);
    lines.push(`🕐 调度类型: ${task.schedule.scheduleType}`);
    lines.push('');
    lines.push('📨 === 任务请求 === 📨');
    lines.push(`RequestId: ${request.requestId}`);
    lines.push(`RequestType: ${request.requestType}`);
    lines.push(`RequestDescription: ${request.requestDescription}`);
    lines.push(`TaskTime: ${request.taskTime}`);
    lines.push(`RequestPageUri: ${request.requestPageUri}`);

    return lines.join('\n');
  }

  /**
   * 添加日志
   */
  private appendLog(message: string): void {
    const timestamp = new Date().toLocaleTimeString();
    const logLine = `[${timestamp}] ${message}`;
    this.logText = this.logText.length === 0 ? logLine : `${this.logText}\n${logLine}`;
    hilog.info(0x0523, 'ConcertDetail', '%{public}s', message);
  }

  /**
   * 跳转到票务元服务
   */
  private goToTicketService() {
    try {
      const applinkingUrl = 'https://hoas.drcn.agconnect.link/Ajjnz';
      const context = getContext(this) as common.UIAbilityContext;

      context.openLink(applinkingUrl)
        .then(() => {
          console.info('openAtomicService succeed');
        })
        .catch((err: Error) => {
          console.error('openAtomicService failed:', err.message || JSON.stringify(err));
          this.showToast('暂时无法打开抢票服务，请稍后重试');
        });
    } catch (error) {
      console.error('Error opening ticket service:', JSON.stringify(error));
      this.showToast('打开抢票服务失败');
    }
  }

  /**
   * 显示Toast提示
   */
  private showToast(message: string) {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 3000
      });
    } catch (error) {
      console.error('Failed to show toast:', JSON.stringify(error));
    }
  }

  private buildConcertUiTree(): string {
    return `Page (id: concert_detail_page) [演唱会详情页]
  Text (id: concert_title) [***演唱会] bounds(16,20,360,72)
  Text (id: concert_show_time) [2026.05.23 19:00 周六] bounds(250,420,860,470)
  Text (id: concert_sale_time) [3月10日 15:00开抢，仅${this.formatCountdown()}] bounds(120,1540,900,1588)
  TextArea (id: ticket_request_input) [${this.userInput}] bounds(48,1220,1032,1340)
  Button (id: detect_ticket_task_button) [智能识别抢票任务] bounds(48,1360,1032,1448)
  Button (id: wish_button) [想看] bounds(48,1620,240,1696)
  Button (id: rush_ticket_button) [抢票] bounds(820,1620,1000,1696)
  Link (id: ticket_service_link) [https://hoas.drcn.agconnect.link/Ajjnz] bounds(760,1620,1040,1700)
`;
  }
}
