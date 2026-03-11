import router from '@ohos.router';

@Entry
@Component
struct Index {
  build() {
    Column({ space: 20 }) {
      Text('TicketAgent GUI Prototype')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111827');

      Text('最小原型入口：进入演唱会详情页，输入“帮我抢票”，页面会自动定位并点击“抢票”按钮。')
        .width('100%')
        .fontSize(15)
        .lineHeight(24)
        .fontColor('#4B5563');

      Button('进入抢票页面')
        .width('100%')
        .height(52)
        .backgroundColor('#EA580C')
        .fontColor('#FFFFFF')
        .fontSize(18)
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
    .padding(24)
    .backgroundColor('#FFF7ED');
  }
}
