import router from '@ohos.router';

@Entry
@Component
struct Index {
  @State message: string = '票务智能代理系统';

  build() {
    Column({ space: 24 }) {
      Text(this.message)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1E1E1E')
        .margin({ top: 40 });

      Text('基于大模型的智能票务助手')
        .fontSize(16)
        .fontColor('#666666')
        .margin({ bottom: 40 });

      Column({ space: 16 }) {
        Button('演唱会详情页面')
          .width('80%')
          .height(56)
          .fontSize(18)
          .backgroundColor('#9C27B0')
          .onClick(() => {
            router.pushUrl({ url: 'pages/ConcertDetailPage' })
              .catch((err: Error) => {
                console.error('Navigation failed:', err.message);
              });
          });

        Button('GUI操作测试')
          .width('80%')
          .height(56)
          .fontSize(18)
          .backgroundColor('#4CAF50')
          .onClick(() => {
            router.pushUrl({ url: 'pages/GuiTestPage' })
              .catch((err: Error) => {
                console.error('Navigation failed:', err.message);
              });
          });

        Button('手机端GUI测试')
          .width('80%')
          .height(56)
          .fontSize(18)
          .backgroundColor('#F97316')
          .onClick(() => {
            router.pushUrl({ url: 'pages/MobileGuiTestPage' })
              .catch((err: Error) => {
                console.error('Navigation failed:', err.message);
              });
          });

        Button('UI组件树测试')
          .width('80%')
          .height(56)
          .fontSize(18)
          .backgroundColor('#2196F3')
          .onClick(() => {
            router.pushUrl({ url: 'pages/UiTreeTestPage' })
              .catch((err: Error) => {
                console.error('Navigation failed:', err.message);
              });
          });
      }

      Divider()
        .width('80%')
        .color('#E0E0E0')
        .margin({ top: 20, bottom: 20 });

      Column({ space: 12 }) {
        Text('功能特点')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333');

        Column({ space: 8 }) {
          Row() {
            Text('🤖')
              .fontSize(20);
            Text('智能任务识别：支持演出票、火车票、红包等多种任务类型')
              .fontSize(14)
              .fontColor('#555555')
              .layoutWeight(1);
          }
          .width('80%')
          .alignItems(VerticalAlign.Top);

          Row() {
            Text('📸')
              .fontSize(20);
            Text('多模态分析：结合图像、UI组件树和用户指令进行分析')
              .fontSize(14)
              .fontColor('#555555')
              .layoutWeight(1);
          }
          .width('80%')
          .alignItems(VerticalAlign.Top);

          Row() {
            Text('🎯')
              .fontSize(20);
            Text('GUI自动化：基于大模型的屏幕操作控制')
              .fontSize(14)
              .fontColor('#555555')
              .layoutWeight(1);
          }
          .width('80%')
          .alignItems(VerticalAlign.Top);

          Row() {
            Text('⏰')
              .fontSize(20);
            Text('时间智能提取：从图像和文本中自动识别时间信息')
              .fontSize(14)
              .fontColor('#555555')
              .layoutWeight(1);
          }
          .width('80%')
          .alignItems(VerticalAlign.Top);
        }
      }

      Blank()
        .layoutWeight(1);

      Text('基于GPT-5.4驱动')
        .fontSize(12)
        .fontColor('#999999')
        .margin({ bottom: 20 });
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 20, bottom: 20 })
    .backgroundColor('#FAFAFA');
  }
}
