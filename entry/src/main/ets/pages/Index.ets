import router from '@ohos.router';

@Entry
@Component
struct Index {
  build() {
    Column({ space: 20 }) {
      Text('最小化智能抢票识别')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827')
        .textAlign(TextAlign.Center);

      Text('当前工程只保留智能抢票任务识别入口。')
        .fontSize(15)
        .fontColor('#4B5563')
        .textAlign(TextAlign.Center);

      Button('进入识别页')
        .width('100%')
        .height(52)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#DC2626')
        .borderRadius(14)
        .onClick(() => {
          router.pushUrl({ url: 'pages/ConcertDetailPage' })
            .catch((err: Error) => {
              console.error('Navigation failed:', err.message);
            });
        });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: 24, right: 24, top: 24, bottom: 24 })
    .backgroundColor('#FFFFFF');
  }
}
