import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { loadRawfileImageBase64 } from './mini/MiniVision';
import { identifyTaskFromImageBase64, EnhancedTaskResult } from './mini/MiniLlm';

@Entry
@Component
struct ConcertDetailPage {
  @State isProcessing: boolean = false;
  @State resultText: string = '';
  @State logText: string = '';

  private readonly promptText: string = '等下帮我抢这张演唱会门票';
  private readonly sampleImagePath: string = 'maoyan_small.jpg';

  build() {
    Column({ space: 16 }) {
      Text('智能抢票任务识别')
        .width('100%')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
        .textAlign(TextAlign.Center);

      Text('只保留最小识别功能。点击按钮后，会读取 rawfile 内置参考图 maoyan_small.jpg 并发送给大模型识别。')
        .width('100%')
        .fontSize(14)
        .lineHeight(22)
        .fontColor('#4B5563')
        .textAlign(TextAlign.Center);

      Button(this.isProcessing ? '识别中...' : '智能识别抢票任务')
        .width('100%')
        .height(52)
        .enabled(!this.isProcessing)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#DC2626')
        .borderRadius(14)
        .onClick(() => {
          void this.processTicketRequest();
        });

      if (this.logText) {
        Text(this.logText)
          .width('100%')
          .fontSize(12)
          .lineHeight(18)
          .fontColor('#374151')
          .backgroundColor('#F3F4F6')
          .padding(12)
          .borderRadius(12);
      }

      if (this.resultText) {
        Text(this.resultText)
          .width('100%')
          .fontSize(13)
          .lineHeight(20)
          .fontColor('#111827')
          .backgroundColor('#ECFDF5')
          .padding(14)
          .borderRadius(12);
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 20, right: 20, top: 24, bottom: 24 })
    .backgroundColor('#FFFFFF');
  }

  private async processTicketRequest(): Promise<void> {
    if (this.isProcessing) {
      return;
    }

    this.isProcessing = true;
    this.resultText = '';
    this.logText = '';
    this.appendLog('开始处理抢票请求');

    try {
      const context = getContext(this) as common.UIAbilityContext;
      const sampleAttachment = await loadRawfileImageBase64(context, this.sampleImagePath);
      this.appendLog(`参考图加载完成: ${sampleAttachment.name}`);

      const taskResult: EnhancedTaskResult = await identifyTaskFromImageBase64(
        this.promptText,
        sampleAttachment.base64,
        sampleAttachment.mimeType
      );

      this.resultText = [
        `任务类型: ${taskResult.taskType}`,
        `任务标题: ${taskResult.title}`,
        `票务开抢时间: ${taskResult.ticketSaleStartTime || '未识别到时间'}`,
        `开始表演时间: ${taskResult.performanceStartTime || '未识别到'}`,
        `票价范围: ${taskResult.priceRange || '未识别到'}`,
        `抢票平台: ${taskResult.ticketPlatform || '未识别到'}`,
        `演出城市: ${taskResult.city || '未识别到'}`,
        `演出场馆: ${taskResult.venue || '未识别到'}`,
        `演出阵容: ${taskResult.lineup || '未识别到'}`,
        `其他信息: ${taskResult.otherInfo || '无'}`
      ].join('\n');
      this.appendLog('识别完成');
    } catch (error) {
      const err = error as Error;
      this.appendLog(`处理失败: ${err.message || JSON.stringify(error)}`);
    } finally {
      this.isProcessing = false;
    }
  }

  private appendLog(message: string): void {
    const line = `[${new Date().toLocaleTimeString()}] ${message}`;
    this.logText = this.logText.length === 0 ? line : `${this.logText}\n${line}`;
    hilog.info(0x0523, 'ConcertDetail', '%{public}s', message);
  }
}
