import { hilog } from '@kit.PerformanceAnalysisKit';
import image from '@ohos.multimedia.image';
import http from '@ohos.net.http';
import { util } from '@kit.ArkTS';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'LlmService';

interface LlmConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
}

// 大模型配置
const LLM_CONFIG: LlmConfig = {
  baseUrl: 'https://api.v3.cm',
  apiKey: 'sk-mqIx6VohpghY3Fe26a070dE4775841D7BcFc7b073c2a0257',
  model: 'gpt-5.4'
};

export interface LlmRequestBody {
  model: string;
  messages: LlmMessage[];
  temperature: number;
  max_tokens: number;
}

export interface HttpRequestHeaders {
  'Content-Type': string;
  'Authorization': string;
}

export interface LlmImageUrl {
  url: string;
  detail?: 'low' | 'high' | 'auto';
}

export interface LlmMessage {
  role: 'system' | 'user' | 'assistant';
  content: LlmMessageContent[];
}

export interface LlmMessageContent {
  type: 'text' | 'image_url';
  text?: string;
  image_url?: LlmImageUrl;
}

export interface LlmTaskIdentificationResult {
  taskType: 'concertTicket' | 'trainTicket' | 'redPacket' | 'taxi' | 'reminder' | 'generic';
  title: string;
  timeText: string;
  confidence: number;
  extraInfo?: string;
}

export interface LlmMultimodalRequest {
  userText: string;
  imageBase64?: string;
  uiComponentTree?: string;
  imageMimeType?: 'image/png' | 'image/jpeg';
  imageDetail?: 'low' | 'high' | 'auto';
}

export interface TicketScreenPlanOptions {
  includeUiTree?: boolean;
  retryHint?: string;
  imageDetail?: 'low' | 'high' | 'auto';
  imageMimeType?: 'image/png' | 'image/jpeg';
}

interface LlmApiResponse {
  choices: LlmChoice[];
}

interface LlmChoice {
  message: LlmChoiceMessage;
}

interface LlmChoiceMessage {
  content: string;
}

interface ParsedTaskResponse {
  taskType?: string;
  title?: string;
  timeText?: string;
  confidence?: number;
  extraInfo?: string;
}

interface ParsedTaskExecutionStep {
  done?: boolean;
  action?: 'scroll' | 'click';
  targetId?: string;
  targetText?: string;
  direction?: 'up' | 'down';
  x?: number;
  y?: number;
  reason?: string;
}

interface ParsedBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface GuiAction {
  type: 'tap' | 'swipe' | 'input' | 'wait';
  targetId?: string;
  x?: number;
  y?: number;
  startX?: number;
  startY?: number;
  endX?: number;
  endY?: number;
  direction?: 'up' | 'down' | 'left' | 'right';
  text?: string;
  milliseconds?: number;
  description: string;
}

export interface TicketTaskExecutionStep {
  done: boolean;
  action: 'scroll' | 'click';
  targetId?: string;
  targetText?: string;
  direction?: 'up' | 'down';
  x?: number;
  y?: number;
  reason: string;
}

export class LlmService {
  private static instance: LlmService;

  public static getInstance(): LlmService {
    if (!LlmService.instance) {
      LlmService.instance = new LlmService();
    }
    return LlmService.instance;
  }

  /**
   * 识别任务类型并提取信息
   */
  async identifyTaskFromMultimodal(request: LlmMultimodalRequest): Promise<LlmTaskIdentificationResult> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Starting multimodal task identification');

    const messages: LlmMessage[] = [
      {
        role: 'system',
        content: [{
          type: 'text',
          text: `你是一个任务识别专家。用户会提供文本指令，可能还包括屏幕截图和UI组件树。

请分析用户的需求并识别任务类型：
- concertTicket: 抢演出票/演唱会门票
- trainTicket: 抢火车票/高铁票
- redPacket: 红包相关任务
- taxi: 打车/约车任务
- reminder: 提醒类任务
- generic: 其他通用任务

返回JSON格式：
{
  "taskType": "任务类型",
  "title": "任务标题，尽量具体，例如演唱会名称/出发地-目的地/红包发送方",
  "timeText": "时间信息(HH:MM或YYYY-MM-DD HH:MM)",
  "confidence": 0.0-1.0,
  "extraInfo": "附加信息(可选)"
}

识别原则：
- 若截图或UI树明显是演唱会详情页、抢票页、票务页，优先识别为 concertTicket。
- title 优先从界面标题提取，例如“***演唱会”。
- timeText 优先提取“开抢时间/演出时间/发车时间/截止时间”等与执行最相关的时间。
- 只输出 JSON，不要附带 markdown。`
        }]
      }
    ];

    // 构建用户消息内容
    const userContent: LlmMessageContent[] = [
      {
        type: 'text',
        text: `用户指令：${request.userText}`
      }
    ];

    // 添加UI组件树信息
    if (request.uiComponentTree) {
      userContent.push({
        type: 'text',
        text: `UI组件树：\n${request.uiComponentTree}`
      });
    }

    // 添加图片信息
    if (request.imageBase64) {
      const imageUrl: LlmImageUrl = {
        url: `data:${request.imageMimeType || 'image/png'};base64,${request.imageBase64}`,
        detail: request.imageDetail || 'low'
      };

      userContent.push({
        type: 'image_url',
        image_url: imageUrl
      });
    }

    messages.push({
      role: 'user',
      content: userContent
    });

    try {
      const response = await this.callLlmApi(messages);
      return this.parseTaskIdentificationResponse(response);
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Task identification failed: %{public}s', JSON.stringify(error));
      throw new Error('Task identification failed');
    }
  }

  /**
   * 生成GUI操作指令
   */
  async generateGuiActions(
    userInstruction: string,
    screenshotBase64: string,
    uiComponentTree?: string
  ): Promise<GuiAction[]> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Starting GUI action generation');

    const imageUrl: LlmImageUrl = {
      url: `data:image/png;base64,${screenshotBase64}`,
      detail: 'high'
    };

    const imageContent: LlmMessageContent = {
      type: 'image_url',
      image_url: imageUrl
    };

    const messages: LlmMessage[] = [
      {
        role: 'system',
        content: [{
          type: 'text',
          text: `你是一个GUI自动化专家。根据用户指令和当前屏幕状态，生成所需的操作步骤。

支持的操作类型：
- tap: 点击操作 {type: "tap", targetId?: string, x?: number, y?: number, description: string}
- swipe: 滑动操作 {type: "swipe", targetId?: string, direction?: "up"|"down"|"left"|"right", startX?: number, startY?: number, endX?: number, endY?: number, description: string}
- input: 输入文本 {type: "input", targetId?: string, text: string, x?: number, y?: number, description: string}
- wait: 等待 {type: "wait", milliseconds: number, description: string}

要求：
- 如果 UI组件树里有明确的 id，优先输出 targetId。
- 生成 1 到 6 步，保证顺序可执行。
- 只输出 JSON 数组，不要附带解释。`
        }]
      },
      {
        role: 'user',
        content: [
          {
            type: 'text',
            text: `用户指令：${userInstruction}${uiComponentTree ? '\nUI组件树：\n' + uiComponentTree : ''}`
          },
          imageContent
        ]
      }
    ];

    try {
      const response = await this.callLlmApi(messages);
      const parsedActions = this.parseGuiActionsResponse(response);
      const sourceActions = parsedActions.length > 0 ? parsedActions : this.buildFallbackGuiActions(userInstruction);
      return this.normalizeGuiActions(sourceActions, userInstruction, uiComponentTree);
    } catch (error) {
      const err = error as Error;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'GUI action generation failed: %{public}s', err.message || JSON.stringify(error));
      return this.normalizeGuiActions(this.buildFallbackGuiActions(userInstruction), userInstruction, uiComponentTree);
    }
  }

  async planTicketTaskExecution(
    requestDescription: string,
    requestPageUri: string,
    uiComponentTree: string
  ): Promise<TicketTaskExecutionStep> {
    const messages: LlmMessage[] = [
      {
        role: 'system',
        content: [{
          type: 'text',
          text: `你是一个手机端 GUI 任务执行规划器。

已知前置步骤“跳转到请求页面”已经完成。你现在只需要根据请求参数和当前页面 UI 组件树，规划下一步：
- 如果页面里已经看到了抢票按钮，则输出 click
- 如果还没看到抢票按钮，则输出 scroll，并给出 up 或 down

返回 JSON：
{
  "done": false,
  "action": "click|scroll",
  "targetId": "可选，如 rush_ticket_button",
  "targetText": "可选，如 抢票",
  "direction": "up|down",
  "reason": "原因"
}

约束：
- 只输出 JSON
- 如果页面已有按钮，优先 click，不要继续 scroll
- concert detail page 中按钮文本通常为“抢票”`
        }]
      },
      {
        role: 'user',
        content: [{
          type: 'text',
          text: `请求页面URI: ${requestPageUri}\n请求描述: ${requestDescription}\n当前UI组件树:\n${uiComponentTree}`
        }]
      }
    ];

    try {
      const response = await this.callLlmApi(messages);
      const parsed = this.parseTicketExecutionStep(response);
      return parsed;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Ticket task planning failed: %{public}s', JSON.stringify(error));
      return this.fallbackTicketExecutionStep(uiComponentTree);
    }
  }

  async planTicketTaskExecutionFromScreen(
    requestDescription: string,
    requestPageUri: string,
    screenshotBase64: string,
    uiComponentTree?: string,
    options: TicketScreenPlanOptions = {}
  ): Promise<TicketTaskExecutionStep> {
    const includeUiTree = options.includeUiTree === true && !!uiComponentTree;
    const promptLines: string[] = [
      `请求页面URI: ${requestPageUri}`,
      `请求描述: ${requestDescription}`,
      '截图说明: 当前提供的是屏幕下半部分裁剪图，不是整屏截图。',
      '任务要求: 识别“抢票/立即抢票/马上抢票/去抢票/开抢”这类按钮的当前位置。'
    ];
    if (options.retryHint) {
      promptLines.push(`重试提示: ${options.retryHint}`);
    }
    if (includeUiTree) {
      promptLines.push(`当前UI组件树:\n${uiComponentTree}`);
    }

    const messages: LlmMessage[] = [
      {
        role: 'system',
        content: [{
          type: 'text',
          text: `你是一个抢票页面屏幕定位助手。

优先依据截图判断，不要臆测按钮位置：
- 当前图片是屏幕下半部分裁剪图，只关注这张图里真实可见的内容
- 如果图片里明确看到了抢票相关按钮，返回 click
- 抢票相关按钮文本可能是：抢票、立即抢票、马上抢票、抢这张票、立即抢这张票、去抢票、开抢
- 如果图片里没有明确看到目标按钮，返回 scroll，不要伪造 click 坐标
- 只有在当前图片中清晰看到按钮时，才能返回 x 和 y
- x/y 必须基于“当前这张裁剪图”的左上角(0,0)，不是整屏坐标
- 如果提供了 UI 树，它只是辅助信息；当 UI 树和截图冲突时，以截图是否真的可见为准

只输出 JSON：
{
  "done": false,
  "action": "click|scroll",
  "targetText": "可选，按钮文案",
  "direction": "up|down",
  "x": 0,
  "y": 0,
  "reason": "原因"
}`
        }]
      },
      {
        role: 'user',
        content: [
          {
            type: 'text',
            text: promptLines.join('\n')
          },
          {
            type: 'image_url',
            image_url: {
              url: `data:${options.imageMimeType || 'image/png'};base64,${screenshotBase64}`,
              detail: options.imageDetail || 'low'
            }
          }
        ]
      }
    ];

    try {
      const response = await this.callLlmApi(messages);
      return this.parseTicketExecutionStep(response);
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Ticket screen planning failed: %{public}s', JSON.stringify(error));
      return this.fallbackTicketExecutionStep(uiComponentTree);
    }
  }

  /**
   * 调用大模型API
   */
  private async callLlmApi(messages: LlmMessage[]): Promise<string> {
    const httpRequest = http.createHttp();

    try {
      const requestBody: LlmRequestBody = {
        model: LLM_CONFIG.model,
        messages: messages,
        temperature: 0.1,
        max_tokens: 2000
      };

      const headers: HttpRequestHeaders = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${LLM_CONFIG.apiKey}`
      };

      const response = await httpRequest.request(`${LLM_CONFIG.baseUrl}/v1/chat/completions`, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(requestBody),
        expectDataType: http.HttpDataType.STRING
      });

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}: ${response.result}`);
      }

      const result = JSON.parse(response.result as string) as LlmApiResponse;
      let content: string = '';

      if (result && result.choices && result.choices.length > 0 && result.choices[0].message) {
        content = result.choices[0].message.content;
      }

      if (!content) {
        throw new Error('No content in LLM response');
      }

      hilog.info(LOG_DOMAIN, LOG_TAG, 'LLM API call successful, response length: %{public}d', content.length);
      return content;
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 解析任务识别响应
   */
  private parseTaskIdentificationResponse(response: string): LlmTaskIdentificationResult {
    try {
      // 尝试提取JSON部分
      const jsonMatch = response.match(/\{[\s\S]*\}/);
      const jsonStr = jsonMatch ? jsonMatch[0] : response;
      const parsed = JSON.parse(jsonStr) as ParsedTaskResponse;

      const validTaskTypes: string[] = [
        'concertTicket', 'trainTicket', 'redPacket', 'taxi', 'reminder', 'generic'
      ];

      const isValidTaskType = parsed.taskType && validTaskTypes.includes(parsed.taskType);
      const taskType: 'concertTicket' | 'trainTicket' | 'redPacket' | 'taxi' | 'reminder' | 'generic' =
        isValidTaskType ?
          parsed.taskType as ('concertTicket' | 'trainTicket' | 'redPacket' | 'taxi' | 'reminder' | 'generic') :
          'generic';

      return {
        taskType: taskType,
        title: parsed.title || '未知任务',
        timeText: parsed.timeText || '',
        confidence: parsed.confidence || 0.5,
        extraInfo: parsed.extraInfo
      };
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to parse task identification response: %{public}s', JSON.stringify(error));
      // 回退解析
      return this.fallbackParseTaskIdentification(response);
    }
  }

  /**
   * 回退解析任务识别
   */
  private fallbackParseTaskIdentification(response: string): LlmTaskIdentificationResult {
    const normalized = response.toLowerCase();

    let taskType: 'concertTicket' | 'trainTicket' | 'redPacket' | 'taxi' | 'reminder' | 'generic' = 'generic';
    let title = '通用任务';

    if (normalized.includes('演出') || normalized.includes('演唱会') || normalized.includes('音乐会')) {
      taskType = 'concertTicket';
      title = '抢演出票';
    } else if (normalized.includes('火车票') || normalized.includes('高铁')) {
      taskType = 'trainTicket';
      title = '抢火车票';
    } else if (normalized.includes('红包')) {
      taskType = 'redPacket';
      title = '红包任务';
    } else if (normalized.includes('打车') || normalized.includes('约车') || normalized.includes('出租车')) {
      taskType = 'taxi';
      title = '打车任务';
    } else if (normalized.includes('提醒') || normalized.includes('闹钟')) {
      taskType = 'reminder';
      title = '提醒任务';
    }

    // 简单时间提取
    const timeMatch = response.match(/(\d{1,2}):(\d{1,2})/);
    const timeText = timeMatch ? timeMatch[0] : '';

    return {
      taskType,
      title,
      timeText,
      confidence: 0.3,
      extraInfo: response.substring(0, 100)
    };
  }

  /**
   * 解析GUI操作响应
   */
  private parseGuiActionsResponse(response: string): GuiAction[] {
    try {
      // 尝试提取JSON数组部分
      const jsonMatch = response.match(/\[[\s\S]*\]/);
      const jsonStr = jsonMatch ? jsonMatch[0] : response;
      const parsed: GuiAction | GuiAction[] = JSON.parse(jsonStr);

      if (Array.isArray(parsed)) {
        return parsed as GuiAction[];
      }

      return [parsed] as GuiAction[];
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to parse GUI actions response: %{public}s', JSON.stringify(error));
      return [];
    }
  }

  private normalizeGuiActions(actions: GuiAction[], userInstruction: string, uiComponentTree?: string): GuiAction[] {
    const availableIds = this.extractUiIds(uiComponentTree);
    const normalizedActions: GuiAction[] = [];

    for (const action of actions) {
      const normalizedAction: GuiAction = {
        type: action.type,
        targetId: action.targetId,
        x: action.x,
        y: action.y,
        startX: action.startX,
        startY: action.startY,
        endX: action.endX,
        endY: action.endY,
        direction: action.direction,
        text: action.text,
        milliseconds: action.milliseconds,
        description: action.description || this.buildActionDescription(action)
      };

      if (!normalizedAction.targetId) {
        normalizedAction.targetId = this.inferTargetIdFromAction(normalizedAction, userInstruction, availableIds);
      }

      if (normalizedAction.type === 'swipe' && !normalizedAction.direction) {
        normalizedAction.direction = this.inferDirection(normalizedAction.description, userInstruction);
      }

      if (normalizedAction.type === 'input' && !normalizedAction.text) {
        normalizedAction.text = this.extractQuotedText(userInstruction) || '测试';
      }

      if (normalizedAction.type === 'wait' && !normalizedAction.milliseconds) {
        normalizedAction.milliseconds = 1000;
      }

      if (this.isActionExecutable(normalizedAction)) {
        normalizedActions.push(normalizedAction);
      }
    }

    return normalizedActions;
  }

  private buildFallbackGuiActions(userInstruction: string): GuiAction[] {
    const actions: GuiAction[] = [];
    const normalized = userInstruction.toLowerCase();
    const quotedText = this.extractQuotedText(userInstruction);

    if (normalized.includes('火车票')) {
      actions.push({ type: 'tap', targetId: 'tab_train', description: '切换到火车票标签' });
    } else if (normalized.includes('红包')) {
      actions.push({ type: 'tap', targetId: 'tab_red_packet', description: '切换到红包标签' });
    } else if (normalized.includes('演出') || normalized.includes('演唱会')) {
      actions.push({ type: 'tap', targetId: 'tab_concert', description: '切换到演出标签' });
    }

    if (normalized.includes('打开表单')) {
      actions.push({ type: 'tap', targetId: 'open_form_button', description: '打开表单' });
    }

    if (normalized.includes('抢票')) {
      actions.push({ type: 'tap', targetId: 'rush_ticket_button', description: '点击抢票按钮' });
    }

    if (normalized.includes('输入') || quotedText.length > 0) {
      actions.push({
        type: 'input',
        targetId: 'note_input',
        text: quotedText || '测试',
        description: '在备注输入框输入文本'
      });
    }

    if (normalized.includes('确认') || normalized.includes('提交')) {
      actions.push({ type: 'tap', targetId: 'submit_note_button', description: '提交表单' });
    }

    if (normalized.includes('滑动')) {
      actions.push({
        type: 'swipe',
        targetId: 'feed_list',
        direction: normalized.includes('向上') ? 'up' : 'down',
        description: '滑动任务列表'
      });
    }

    if (normalized.includes('等待')) {
      actions.push({
        type: 'wait',
        milliseconds: this.extractWaitTime(userInstruction),
        description: '等待页面状态稳定'
      });
    }

    if (normalized.includes('点赞')) {
      actions.push({ type: 'tap', targetId: 'like_button', description: '点击点赞按钮' });
    }

    return actions;
  }

  private parseTicketExecutionStep(response: string): TicketTaskExecutionStep {
    try {
      const jsonMatch = response.match(/\{[\s\S]*\}/);
      const jsonStr = jsonMatch ? jsonMatch[0] : response;
      const parsed = JSON.parse(jsonStr) as ParsedTaskExecutionStep;

      if (parsed.action === 'click') {
        return {
          done: parsed.done ?? false,
          action: 'click',
          targetId: parsed.targetId,
          targetText: parsed.targetText || '抢票',
          x: parsed.x,
          y: parsed.y,
          reason: parsed.reason || '已识别到抢票按钮'
        };
      }

      return {
        done: parsed.done ?? false,
        action: 'scroll',
        direction: parsed.direction === 'up' ? 'up' : 'down',
        reason: parsed.reason || '当前屏幕未找到抢票按钮，先滚动查找'
      };
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to parse ticket execution step: %{public}s', JSON.stringify(error));
      return this.fallbackTicketExecutionStep(response);
    }
  }

  private fallbackTicketExecutionStep(uiComponentTree?: string): TicketTaskExecutionStep {
    if (!uiComponentTree) {
      return {
        done: false,
        action: 'scroll',
        direction: 'down',
        reason: '未提供UI树且截图未返回可靠点击坐标，默认向下继续查找'
      };
    }

    const rootBounds = this.extractRootBounds(uiComponentTree);
    const ticketBounds = this.extractTicketBounds(uiComponentTree);

    if (ticketBounds && rootBounds) {
      if (ticketBounds.top > rootBounds.bottom) {
        return {
          done: false,
          action: 'scroll',
          direction: 'down',
          targetId: 'rush_ticket_button',
          targetText: '抢票',
          reason: 'UI树中已找到抢票按钮，但它位于当前可视区域下方'
        };
      }
      if (ticketBounds.bottom < rootBounds.top) {
        return {
          done: false,
          action: 'scroll',
          direction: 'up',
          targetId: 'rush_ticket_button',
          targetText: '抢票',
          reason: 'UI树中已找到抢票按钮，但它位于当前可视区域上方'
        };
      }
    }

    if (uiComponentTree.includes('rush_ticket_button') || uiComponentTree.includes('[抢票]')) {
      return {
        done: false,
        action: 'click',
        targetId: 'rush_ticket_button',
        targetText: '抢票',
        reason: 'UI树中已找到抢票按钮'
      };
    }

    return {
      done: false,
      action: 'scroll',
      direction: 'down',
      reason: 'UI树中未找到抢票按钮，向下滚动继续查找'
    };
  }

  private extractRootBounds(uiComponentTree: string): ParsedBounds | undefined {
    const match = uiComponentTree.match(/(?:Page|Window|Scroll|ContentArea) .*?bounds\((\d+),(\d+),(\d+),(\d+)\)/);
    return this.parseBoundsMatch(match);
  }

  private extractTicketBounds(uiComponentTree: string): ParsedBounds | undefined {
    const lines = uiComponentTree.split('\n');
    for (const line of lines) {
      if (!/抢票|立即抢票|马上抢票|抢这张票|立即抢这张票|去抢票|开抢/.test(line) &&
        !line.includes('rush_ticket_button')) {
        continue;
      }
      const match = line.match(/bounds\((\d+),(\d+),(\d+),(\d+)\)/);
      const parsed = this.parseBoundsMatch(match);
      if (parsed) {
        return parsed;
      }
    }
    return undefined;
  }

  private parseBoundsMatch(match: RegExpMatchArray | null): ParsedBounds | undefined {
    if (!match) {
      return undefined;
    }
    return {
      left: Number(match[1]),
      top: Number(match[2]),
      right: Number(match[3]),
      bottom: Number(match[4])
    };
  }

  private inferTargetIdFromAction(action: GuiAction, userInstruction: string, availableIds: string[]): string | undefined {
    const combined = `${action.description} ${userInstruction}`;
    const hasId = (id: string): boolean => availableIds.includes(id);

    if (/打开表单/.test(combined) && hasId('open_form_button')) {
      return 'open_form_button';
    }
    if (/(确认|提交)/.test(combined) && hasId('submit_note_button')) {
      return 'submit_note_button';
    }
    if (/点赞/.test(combined) && hasId('like_button')) {
      return 'like_button';
    }
    if (/抢票/.test(combined) && hasId('rush_ticket_button')) {
      return 'rush_ticket_button';
    }
    if (/(输入|备注)/.test(combined) && hasId('note_input')) {
      return 'note_input';
    }
    if (/火车票/.test(combined) && hasId('tab_train')) {
      return 'tab_train';
    }
    if (/红包/.test(combined) && hasId('tab_red_packet')) {
      return 'tab_red_packet';
    }
    if (/(演出|演唱会)/.test(combined) && hasId('tab_concert')) {
      return 'tab_concert';
    }
    if (/滑动/.test(combined) && hasId('feed_list')) {
      return 'feed_list';
    }
    return undefined;
  }

  private extractUiIds(uiComponentTree?: string): string[] {
    if (!uiComponentTree) {
      return [];
    }
    const matches = uiComponentTree.match(/id:\s*([a-zA-Z0-9_]+)/g);
    if (!matches) {
      return [];
    }
    return matches.map(match => match.replace(/id:\s*/, ''));
  }

  private inferDirection(description: string, userInstruction: string): 'up' | 'down' | 'left' | 'right' {
    const combined = `${description} ${userInstruction}`;
    if (combined.includes('向上')) {
      return 'up';
    }
    if (combined.includes('向左')) {
      return 'left';
    }
    if (combined.includes('向右')) {
      return 'right';
    }
    return 'down';
  }

  private extractQuotedText(text: string): string {
    const match = text.match(/[“"]([^”"]+)[”"]/);
    return match ? match[1] : '';
  }

  private extractWaitTime(text: string): number {
    const match = text.match(/(\d+)\s*秒/);
    if (!match) {
      return 1000;
    }
    return Number(match[1]) * 1000;
  }

  private isActionExecutable(action: GuiAction): boolean {
    if (action.type === 'wait') {
      return true;
    }
    if (action.targetId) {
      return true;
    }
    if (action.type === 'tap') {
      return action.x !== undefined && action.y !== undefined;
    }
    if (action.type === 'input') {
      return !!action.text;
    }
    if (action.type === 'swipe') {
      return !!action.direction || (
        action.startX !== undefined &&
        action.startY !== undefined &&
        action.endX !== undefined &&
        action.endY !== undefined
      );
    }
    return false;
  }

  private buildActionDescription(action: GuiAction): string {
    switch (action.type) {
      case 'tap':
        return '点击元素';
      case 'swipe':
        return '滑动页面';
      case 'input':
        return '输入文本';
      case 'wait':
        return '等待页面稳定';
      default:
        return '执行操作';
    }
  }
}

/**
 * 将PixelMap转换为Base64字符串
 */
export interface PixelMapEncodeOptions {
  format?: 'image/png' | 'image/jpeg';
  quality?: number;
}

export async function pixelMapToBase64(
  pixelMap: image.PixelMap,
  options: PixelMapEncodeOptions = {}
): Promise<string> {
  const packer = image.createImagePacker();
  try {
    const arrayBuffer = await packer.packToData(pixelMap, {
      format: options.format || 'image/png',
      quality: options.quality ?? 90
    });
    const uint8Array = new Uint8Array(arrayBuffer);

    // 使用HarmonyOS的Base64工具
    const base64Helper = new util.Base64Helper();
    return base64Helper.encodeToStringSync(uint8Array);
  } finally {
    await packer.release();
  }
}
