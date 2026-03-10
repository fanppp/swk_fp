import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UiTreeService, ClickableElement } from './mini/MiniUiTreeService';
import { captureFullScreenshot, saveScreenshotToAppFiles } from './mini/MiniVision';

@Entry
@Component
struct UiTreeTestPage {
  @State isRunning: boolean = false;
  @State uiTreeText: string = '';
  @State clickableElementsText: string = '';
  @State logText: string = '点击按钮获取当前页面的UI组件树信息';

  build() {
    Column({ space: 16 }) {
      Text('UI组件树获取测试')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1E1E1E');

      Row({ space: 12 }) {
        Button(this.isRunning ? '获取中...' : '获取UI组件树')
          .width('48%')
          .height(48)
          .enabled(!this.isRunning)
          .backgroundColor('#2196F3')
          .onClick(() => {
            void this.captureUiTree();
          });

        Button(this.isRunning ? '分析中...' : '获取可点击元素')
          .width('48%')
          .height(48)
          .enabled(!this.isRunning)
          .backgroundColor('#FF9800')
          .onClick(() => {
            void this.findClickableElements();
          });
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween);

      Row({ space: 12 }) {
        Button('截图并保存')
          .width('48%')
          .height(48)
          .enabled(!this.isRunning)
          .backgroundColor('#4CAF50')
          .onClick(() => {
            void this.takeScreenshot();
          });

        Button('清空内容')
          .width('48%')
          .height(48)
          .enabled(!this.isRunning)
          .backgroundColor('#666666')
          .onClick(() => {
            this.clearContent();
          });
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween);

      // 日志区域
      if (this.logText) {
        Text('操作日志')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .alignSelf(ItemAlign.Start);

        Text(this.logText)
          .width('100%')
          .fontSize(14)
          .lineHeight(18)
          .fontColor('#333333')
          .backgroundColor('#F0F0F0')
          .padding(8)
          .borderRadius(8);
      }

      Scroll() {
        Column({ space: 16 }) {
          // UI组件树信息
          if (this.uiTreeText) {
            Column({ space: 8 }) {
              Text('UI组件树结构')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .alignSelf(ItemAlign.Start);

              Text(this.uiTreeText)
                .width('100%')
                .fontSize(12)
                .lineHeight(16)
                .fontColor('#333333')
                .backgroundColor('#F9F9F9')
                .padding(12)
                .borderRadius(8)
                .fontFamily('monospace');
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);
          }

          // 可点击元素信息
          if (this.clickableElementsText) {
            Column({ space: 8 }) {
              Text('可点击元素列表')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .alignSelf(ItemAlign.Start);

              Text(this.clickableElementsText)
                .width('100%')
                .fontSize(12)
                .lineHeight(16)
                .fontColor('#333333')
                .backgroundColor('#E8F5E8')
                .padding(12)
                .borderRadius(8)
                .fontFamily('monospace');
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start);
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#FFFFFF')
      .padding(8);
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 24, bottom: 24 })
    .backgroundColor('#FAFAFA');
  }

  /**
   * 获取UI组件树
   */
  private async captureUiTree(): Promise<void> {
    if (this.isRunning) {
      return;
    }

    this.isRunning = true;
    this.appendLog('开始获取UI组件树...');

    try {
      const context = getContext(this) as common.UIAbilityContext;
      const uiTreeService = UiTreeService.getInstance();

      // 获取完整的UI组件树
      const fullTree = await uiTreeService.captureUiTree(context);
      this.uiTreeText = fullTree;

      this.appendLog(`✅ UI组件树获取成功，共 ${fullTree.split('\n').length} 行`);
      this.showToast('UI组件树获取完成');
    } catch (error) {
      const err = error as Error;
      this.appendLog(`❌ 获取失败: ${err.message || JSON.stringify(error)}`);
      this.showToast('获取UI组件树失败');
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * 查找可点击元素
   */
  private async findClickableElements(): Promise<void> {
    if (this.isRunning) {
      return;
    }

    this.isRunning = true;
    this.appendLog('开始分析可点击元素...');

    try {
      const context = getContext(this) as common.UIAbilityContext;
      const uiTreeService = UiTreeService.getInstance();

      const clickableElements = await uiTreeService.findClickableElements(context);

      if (clickableElements.length > 0) {
        this.clickableElementsText = this.formatClickableElements(clickableElements);
        this.appendLog(`✅ 找到 ${clickableElements.length} 个可点击元素`);
      } else {
        this.clickableElementsText = '未找到可点击元素';
        this.appendLog('⚠️ 未找到可点击元素');
      }

      this.showToast(`找到 ${clickableElements.length} 个可点击元素`);
    } catch (error) {
      const err = error as Error;
      this.appendLog(`❌ 分析失败: ${err.message || JSON.stringify(error)}`);
      this.showToast('分析可点击元素失败');
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * 截图并保存
   */
  private async takeScreenshot(): Promise<void> {
    if (this.isRunning) {
      return;
    }

    this.isRunning = true;
    this.appendLog('开始截图...');

    try {
      const context = getContext(this) as common.UIAbilityContext;

      // 截取全屏
      const screenshotAttachment = await captureFullScreenshot(context);
      this.appendLog(`截图完成: ${screenshotAttachment.name}`);

      const filePath = await saveScreenshotToAppFiles(context, screenshotAttachment.pixelMap, `uitree_test_${Date.now()}`);
      this.appendLog(`✅ 截图已保存到应用目录: ${filePath}`);

      this.showToast('截图保存成功');
    } catch (error) {
      const err = error as Error;
      this.appendLog(`❌ 截图失败: ${err.message || JSON.stringify(error)}`);
      this.showToast('截图保存失败');
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * 格式化可点击元素列表
   */
  private formatClickableElements(elements: ClickableElement[]): string {
    const lines: string[] = [];
    lines.push('=== 可点击元素列表 ===');
    lines.push('');

    elements.forEach((element, index) => {
      lines.push(`${index + 1}. ${element.type}: ${element.text}`);
      lines.push(`   中心点: (${element.centerX}, ${element.centerY})`);
      lines.push(`   区域: (${element.bounds.left}, ${element.bounds.top}) - (${element.bounds.right}, ${element.bounds.bottom})`);
      lines.push('');
    });

    return lines.join('\n');
  }

  /**
   * 清空内容
   */
  private clearContent(): void {
    this.uiTreeText = '';
    this.clickableElementsText = '';
    this.logText = '';
    this.appendLog('内容已清空');
  }

  /**
   * 添加日志
   */
  private appendLog(message: string): void {
    const timestamp = new Date().toLocaleTimeString();
    const logLine = `[${timestamp}] ${message}`;
    this.logText = this.logText.length === 0 ? logLine : `${this.logText}\n${logLine}`;
    hilog.info(0x0523, 'UiTreeTest', '%{public}s', message);
  }

  /**
   * 显示Toast
   */
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 2000
    });
  }
}
