@Entry
@Component
struct GuiTestPage {
  @State selectedTab: string = '演出';
  @State formOpened: boolean = false;
  @State noteInput: string = '';
  @State submittedNote: string = '暂无提交';
  @State likedCount: number = 0;
  @State feedOffset: number = 0;
  @State statusText: string = '等待外部 GUI Agent 控制';
  @State showResultDialog: boolean = false;
  @State dialogMessage: string = '';

  private readonly feedItems: string[] = [
    '演唱会抢票攻略',
    '高铁候补提醒',
    '红包倒计时活动',
    '酒店秒杀场景',
    '打车券领取入口',
    '周末演出排期',
    '火车票改签提示'
  ];

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Scroll() {
        Column({ space: 16 }) {
          Text('GUI 操作测试页面')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1E1E1E');

          Text('本页不再做页面内打桩执行，只作为外部 GUI Agent 的真实控制目标。')
            .width('100%')
            .fontSize(14)
            .lineHeight(20)
            .fontColor('#4B5563');

          Column({ space: 8 }) {
            Text('推荐外部指令')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .alignSelf(ItemAlign.Start);

            Text('进入GUI操作测试页面，点击抢票按钮，打开表单，在备注输入框输入测试抢票，点击确认提交，向下滑动任务列表，再点击点赞按钮。')
              .width('100%')
              .padding(12)
              .fontSize(13)
              .lineHeight(20)
              .backgroundColor('#F6F7FB')
              .borderRadius(12);
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);

          this.PlaygroundCard();

          Button('重置实验场')
            .width('100%')
            .height(40)
            .backgroundColor('#666666')
            .onClick(() => {
              this.resetPlayground();
            });

          Column({ space: 8 }) {
            Text('当前状态')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .alignSelf(ItemAlign.Start);

            Text(this.statusText)
              .width('100%')
              .fontSize(13)
              .lineHeight(20)
              .padding(12)
              .fontColor('#374151')
              .backgroundColor('#F6F7FB')
              .borderRadius(12);
          }
          .width('100%');
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 24, bottom: 24 });
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF');

      if (this.showResultDialog) {
        this.ResultDialog();
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private ResultDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('执行结果')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827');

        Text(this.dialogMessage)
          .width('100%')
          .fontSize(15)
          .lineHeight(22)
          .fontColor('#374151');

        Button('关闭')
          .width('100%')
          .height(44)
          .backgroundColor('#DC2626')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.showResultDialog = false;
          });
      }
      .width('84%')
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(20)
      .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 12 });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#66000000');
  }

  @Builder
  private PlaygroundCard() {
    Column({ space: 12 }) {
      Row() {
        Text('GUI 自动化实验场')
          .fontSize(18)
          .fontWeight(FontWeight.Medium);
        Blank()
          .layoutWeight(1);
        Text(this.statusText)
          .fontSize(12)
          .fontColor('#0F766E')
          .backgroundColor('#DCFCE7')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(12)
          .maxLines(1);
      }
      .width('100%');

      Row({ space: 8 }) {
        this.TabButton('演出');
        this.TabButton('火车票');
        this.TabButton('红包');
      }
      .width('100%');

      Row({ space: 12 }) {
        Button('打开表单')
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#111827')
          .onClick(() => {
            this.formOpened = true;
            this.statusText = '表单已展开';
          });

        Button(`点赞 ${this.likedCount}`)
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#F43F5E')
          .onClick(() => {
            this.likedCount += 1;
            this.statusText = `点赞完成 ${this.likedCount}`;
          });
      }
      .width('100%');

      Button('抢票')
        .width('100%')
        .height(44)
        .backgroundColor('#DC2626')
        .fontColor('#FFFFFF')
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          this.statusText = '抢票成功';
          this.dialogMessage = '抢票成功！';
          this.showResultDialog = true;
        });

      Column({ space: 8 }) {
        Text('备注输入框')
          .fontSize(14)
          .alignSelf(ItemAlign.Start);

        TextInput({ text: this.noteInput, placeholder: '等待外部 GUI Agent 输入文本' })
          .width('100%')
          .height(42)
          .backgroundColor('#F9FAFB')
          .borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => {
            this.noteInput = value;
            this.statusText = `已输入备注: ${value}`;
          });

        if (this.formOpened) {
          Button('确认提交')
            .width('100%')
            .height(40)
            .backgroundColor('#10B981')
            .onClick(() => {
              this.submittedNote = this.noteInput || '空内容';
              this.statusText = `提交完成: ${this.submittedNote}`;
            });
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(12)
      .backgroundColor('#FFF7ED')
      .borderRadius(12);

      Column({ space: 8 }) {
        Row() {
          Text(`当前标签: ${this.selectedTab}`)
            .fontSize(14);
          Blank()
            .layoutWeight(1);
          Text(`列表位置: ${this.feedOffset + 1}/${this.feedItems.length}`)
            .fontSize(12)
            .fontColor('#6B7280');
        }
        .width('100%');

        ForEach(this.getVisibleFeedItems(), (item: string) => {
          Text(item)
            .width('100%')
            .padding(10)
            .backgroundColor('#F3F4F6')
            .borderRadius(10);
        });

        Row({ space: 12 }) {
          Button('上滑查看')
            .layoutWeight(1)
            .height(38)
            .backgroundColor('#CBD5E1')
            .fontColor('#0F172A')
            .onClick(() => {
              this.feedOffset = Math.max(this.feedOffset - 1, 0);
              this.statusText = `列表上滑到 ${this.feedOffset + 1}`;
            });

          Button('下滑查看更多')
            .layoutWeight(1)
            .height(38)
            .backgroundColor('#CBD5E1')
            .fontColor('#0F172A')
            .onClick(() => {
              this.feedOffset = Math.min(this.feedOffset + 1, this.feedItems.length - 1);
              this.statusText = `列表下滑到 ${this.feedOffset + 1}`;
            });
        }
        .width('100%');
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#F8FAFC')
      .borderRadius(12);

      Text(`最近提交: ${this.submittedNote}`)
        .width('100%')
        .fontSize(13)
        .fontColor('#374151')
        .padding(10)
        .backgroundColor('#EFF6FF')
        .borderRadius(10);
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FCFCFC')
    .borderRadius(16)
    .border({ width: 1, color: '#E5E7EB' });
  }

  @Builder
  private TabButton(label: string) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .backgroundColor(this.selectedTab === label ? '#0F766E' : '#E5E7EB')
      .fontColor(this.selectedTab === label ? '#FFFFFF' : '#111827')
      .onClick(() => {
        this.selectedTab = label;
        this.statusText = `切换到 ${label}`;
      });
  }

  private getVisibleFeedItems(): string[] {
    const start = Math.min(this.feedOffset, Math.max(0, this.feedItems.length - 3));
    return this.feedItems.slice(start, start + 3);
  }

  private resetPlayground(): void {
    this.selectedTab = '演出';
    this.formOpened = false;
    this.noteInput = '';
    this.submittedNote = '暂无提交';
    this.likedCount = 0;
    this.feedOffset = 0;
    this.statusText = '实验场已重置';
    this.showResultDialog = false;
    this.dialogMessage = '';
  }
}
