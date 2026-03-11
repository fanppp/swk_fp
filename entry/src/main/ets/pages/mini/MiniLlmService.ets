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

const LLM_CONFIG: LlmConfig = {
  baseUrl: 'https://api.v3.cm',
  apiKey: 'sk-mqIx6VohpghY3Fe26a070dE4775841D7BcFc7b073c2a0257',
  model: 'gpt-5.4'
};

export type LlmTaskType = 'concertTicket' | 'trainTicket' | 'redPacket' | 'taxi' | 'reminder' | 'generic';

export interface LlmTaskIdentificationResult {
  taskType: LlmTaskType;
  title: string;
  ticketSaleStartTime?: string;
  performanceStartTime?: string;
  priceRange?: string;
  ticketPlatform?: string;
  city?: string;
  venue?: string;
  lineup?: string;
  otherInfo?: string;
}

export interface LlmMultimodalRequest {
  userText: string;
  imageBase64?: string;
  imageMimeType?: 'image/png' | 'image/jpeg' | 'image/webp';
  imageDetail?: 'low' | 'high' | 'auto';
}

interface LlmImageUrl {
  url: string;
  detail?: 'low' | 'high' | 'auto';
}

interface LlmMessageContent {
  type: 'text' | 'image_url';
  text?: string;
  image_url?: LlmImageUrl;
}

interface LlmMessage {
  role: 'system' | 'user';
  content: LlmMessageContent[];
}

interface LlmChoiceMessage {
  content?: string;
  tool_calls?: LlmToolCall[];
}

interface LlmChoice {
  message?: LlmChoiceMessage;
}

interface LlmApiResponse {
  choices?: LlmChoice[];
}

interface JsonSchemaProperty {
  type?: string | string[];
  description?: string;
  enum?: string[];
  items?: JsonSchemaProperty;
}

interface TicketTaskSchemaProperties {
  taskType: JsonSchemaProperty;
  title: JsonSchemaProperty;
  ticketSaleStartTime: JsonSchemaProperty;
  performanceStartTime: JsonSchemaProperty;
  priceRange: JsonSchemaProperty;
  ticketPlatform: JsonSchemaProperty;
  city: JsonSchemaProperty;
  venue: JsonSchemaProperty;
  lineup: JsonSchemaProperty;
  otherInfo: JsonSchemaProperty;
}

interface TicketTaskObjectSchema {
  type: 'object';
  properties: TicketTaskSchemaProperties;
  required: string[];
  additionalProperties: boolean;
}

interface LlmFunctionDefinition {
  name: string;
  description: string;
  strict?: boolean;
  parameters: TicketTaskObjectSchema;
}

interface LlmTool {
  type: 'function';
  function: LlmFunctionDefinition;
}

interface LlmToolCallFunction {
  name?: string;
  arguments?: string;
}

interface LlmToolCall {
  function?: LlmToolCallFunction;
}

interface ChatCompletionPayload {
  model: string;
  messages: LlmMessage[];
  temperature: number;
  max_tokens: number;
  tools?: LlmTool[];
}

interface ParsedTaskResponse {
  taskType?: string;
  title?: string;
  ticketSaleStartTime?: string;
  performanceStartTime?: string;
  priceRange?: string;
  ticketPlatform?: string;
  city?: string;
  venue?: string;
  lineup?: string;
  otherInfo?: string;
  timeText?: string;
  extraInfo?: string;
}

interface JsonParseErrorLike {
  message?: string;
}

interface PixelMapEncodeOptions {
  format: 'image/png' | 'image/jpeg';
  quality: number;
}

interface PixelMapSizeLike {
  width: number;
  height: number;
}

interface PixelMapInfoLike {
  width?: number;
  height?: number;
  size?: PixelMapSizeLike;
}

const TASK_RESULT_SCHEMA: TicketTaskObjectSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['taskType', 'title', 'ticketSaleStartTime'],
  properties: {
    taskType: {
      type: 'string',
      enum: ['concertTicket', 'trainTicket', 'redPacket', 'taxi', 'reminder', 'generic'],
      description: '任务类型'
    },
    title: {
      type: 'string',
      description: '任务标题'
    },
    ticketSaleStartTime: {
      type: 'string',
      description: '票务开抢时间，北京时间 yy-mm-dd hh:mm:ss，无法识别则为空字符串'
    },
    performanceStartTime: {
      type: 'string',
      description: '开始表演时间，北京时间 yy-mm-dd hh:mm:ss，可为空字符串'
    },
    priceRange: {
      type: 'string',
      description: '票价范围，可为空字符串'
    },
    ticketPlatform: {
      type: 'string',
      description: '抢票平台，可为空字符串'
    },
    city: {
      type: 'string',
      description: '演出城市，可为空字符串'
    },
    venue: {
      type: 'string',
      description: '演出场馆，可为空字符串'
    },
    lineup: {
      type: 'string',
      description: '演出阵容，多个名字用顿号连接，可为空字符串'
    },
    otherInfo: {
      type: 'string',
      description: '其他信息，可为空字符串'
    }
  }
};

const TASK_RESULT_TOOL_NAME: string = 'extract_ticket_task';
const TASK_RESULT_TOOL_FUNCTION: LlmFunctionDefinition = {
  name: TASK_RESULT_TOOL_NAME,
  description: 'Extract a ticket-related task from screenshot and user text into structured fields.',
  strict: true,
  parameters: TASK_RESULT_SCHEMA
};
const TASK_RESULT_TOOL: LlmTool = {
  type: 'function',
  function: TASK_RESULT_TOOL_FUNCTION
};

export class LlmService {
  private static instance?: LlmService;

  static getInstance(): LlmService {
    if (!LlmService.instance) {
      LlmService.instance = new LlmService();
    }
    return LlmService.instance;
  }

  async identifyTaskFromMultimodal(request: LlmMultimodalRequest): Promise<LlmTaskIdentificationResult> {
    const promptContent: LlmMessageContent = {
      type: 'text',
      text: `User request: ${request.userText}

Action contract:
1. Call the function ${TASK_RESULT_TOOL_NAME}
2. Fill arguments with English property names only
3. Do not output Chinese property names
4. For unknown values, pass an empty string
5. Do not answer in natural language`
    };

    const userContent: LlmMessageContent[] = [promptContent];
    if (request.imageBase64) {
      const imageUrl: LlmImageUrl = {
        url: `data:${request.imageMimeType || 'image/jpeg'};base64,${request.imageBase64}`,
        detail: request.imageDetail || 'low'
      };
      const imageContent: LlmMessageContent = {
        type: 'image_url',
        image_url: imageUrl
      };
      userContent.push(imageContent);
    }

    const systemContent: LlmMessageContent = {
      type: 'text',
      text: `You are a ticket screenshot structured extractor.
You are not a chat assistant, not a customer service assistant, and not a planner.
Your only job is to call the provided function with extracted fields.

Hard requirements:
- Always call the function ${TASK_RESULT_TOOL_NAME}
- Function arguments must use English property names exactly as defined
- Never invent Chinese property names or translated property names
- Do not output any natural language text
- If extraction is uncertain, use an empty string instead of guessing

Extraction rules:
- concert, live show, or ticket rush scenarios should usually map to concertTicket
- title should prefer the full event title and preserve city/stop information
- performanceStartTime must be the actual show start time, not a countdown or browse time
- ticketSaleStartTime must be the sale or presale start time; if only a countdown exists and cannot be converted reliably, return ""
- If the image shows a clear time like "3月18日 20:18 开抢", normalize it to "26-03-18 20:18:00"
- priceRange should be a compact string such as "280-1399"
- lineup should be a single string joined with "、" when there are multiple names
- otherInfo should contain extra useful facts such as "电子发票；实名制观演；约150分钟"
- If the image conflicts with the user text, trust the image
`
    };

    const systemMessage: LlmMessage = {
      role: 'system',
      content: [systemContent]
    };
    const userMessage: LlmMessage = {
      role: 'user',
      content: userContent
    };

    const response = await this.callLlmApi([systemMessage, userMessage]);
    return this.parseTaskIdentificationResponse(response);
  }

  private async callLlmApi(messages: LlmMessage[]): Promise<string> {
    const httpRequest = http.createHttp();
    const requestStartTime = Date.now();
    try {
      hilog.info(
        LOG_DOMAIN,
        LOG_TAG,
        'LLM request start model=%{public}s messageCount=%{public}d hasImage=%{public}s format=%{public}s tool=%{public}s',
        LLM_CONFIG.model,
        messages.length,
        messages.length > 1 && messages[1].content.length > 1 ? 'true' : 'false',
        'tools',
        TASK_RESULT_TOOL_NAME
      );
      const response = await this.sendChatCompletionRequest(httpRequest, messages);
      const result = JSON.parse(response.result as string) as LlmApiResponse;
      const firstChoice = result.choices && result.choices.length > 0 ? result.choices[0] : undefined;
      const functionArgs = this.extractFunctionArguments(firstChoice);
      if (!functionArgs) {
        throw new Error('No function call arguments in LLM response');
      }
      const requestDuration = Date.now() - requestStartTime;
      hilog.info(
        LOG_DOMAIN,
        LOG_TAG,
        'LLM response received http=%{public}d durationMs=%{public}d functionArgs=%{public}s',
        response.responseCode,
        requestDuration,
        functionArgs
      );
      return functionArgs;
    } catch (error) {
      const requestDuration = Date.now() - requestStartTime;
      hilog.error(
        LOG_DOMAIN,
        LOG_TAG,
        'LLM request failed durationMs=%{public}d error=%{public}s',
        requestDuration,
        this.getParseErrorMessage(error)
      );
      throw new Error(this.getParseErrorMessage(error));
    } finally {
      httpRequest.destroy();
    }
  }

  private async sendChatCompletionRequest(
    httpRequest: http.HttpRequest,
    messages: LlmMessage[]
  ): Promise<http.HttpResponse> {
    const payload: ChatCompletionPayload = {
      model: LLM_CONFIG.model,
      messages,
      temperature: 0.1,
      max_tokens: 1000,
      tools: [TASK_RESULT_TOOL]
    };
    const response = await httpRequest.request(`${LLM_CONFIG.baseUrl}/v1/chat/completions`, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${LLM_CONFIG.apiKey}`
      },
      extraData: JSON.stringify(payload),
      expectDataType: http.HttpDataType.STRING
    });
    if (response.responseCode === 200) {
      return response;
    }
    hilog.error(
      LOG_DOMAIN,
      LOG_TAG,
      'LLM non-200 http=%{public}d structured=%{public}s body=%{public}s',
      response.responseCode,
      'false',
      `${response.result}`
    );
    throw new Error(`HTTP ${response.responseCode}: ${response.result}`);
  }

  private parseTaskIdentificationResponse(response: string): LlmTaskIdentificationResult {
    const parseStartTime = Date.now();
    const parsed = this.parseStructuredResponse(response);
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Parse response success durationMs=%{public}d', Date.now() - parseStartTime);
    return this.toTaskIdentificationResult(parsed);
  }

  private parseStructuredResponse(response: string): ParsedTaskResponse {
    const attempts: string[] = this.buildParseCandidates(response);
    let lastErrorMessage = 'unknown parse error';
    for (let i = 0; i < attempts.length; i++) {
      const candidate = attempts[i];
      if (!candidate) {
        continue;
      }
      try {
        const direct = JSON.parse(candidate) as Object;
        if (typeof direct === 'string') {
          const nested = JSON.parse(direct) as ParsedTaskResponse;
          if (this.isParsedTaskResponse(nested)) {
            return nested;
          }
          continue;
        }
        const parsed = direct as ParsedTaskResponse;
        if (this.isParsedTaskResponse(parsed)) {
          return parsed;
        }
      } catch (error) {
        lastErrorMessage = this.getParseErrorMessage(error);
      }
    }
    throw new Error(lastErrorMessage);
  }

  private buildParseCandidates(response: string): string[] {
    const normalized = response.trim();
    const fenceMatch = normalized.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
    const unfenced = fenceMatch ? fenceMatch[1].trim() : normalized;
    const firstBrace = unfenced.indexOf('{');
    const lastBrace = unfenced.lastIndexOf('}');
    const braceSlice = firstBrace >= 0 && lastBrace > firstBrace ? unfenced.substring(firstBrace, lastBrace + 1) : '';
    const unescapedQuoted = unfenced.startsWith('"') && unfenced.endsWith('"') ? unfenced : '';
    const candidates: string[] = [
      normalized,
      unfenced,
      braceSlice,
      unescapedQuoted
    ];
    return this.uniqueNonEmpty(candidates);
  }

  private uniqueNonEmpty(values: string[]): string[] {
    const result: string[] = [];
    for (let i = 0; i < values.length; i++) {
      const value = values[i].trim();
      if (!value || result.includes(value)) {
        continue;
      }
      result.push(value);
    }
    return result;
  }

  private isParsedTaskResponse(value: ParsedTaskResponse): boolean {
    return typeof value === 'object' && value !== null && (
      typeof value.taskType === 'string' ||
      typeof value.title === 'string' ||
      typeof value.ticketSaleStartTime === 'string'
    );
  }

  private extractFunctionArguments(choice?: LlmChoice): string {
    if (!choice || !choice.message || !choice.message.tool_calls || choice.message.tool_calls.length === 0) {
      return '';
    }
    const toolCall = choice.message.tool_calls[0];
    if (!toolCall.function || toolCall.function.name !== TASK_RESULT_TOOL_NAME || !toolCall.function.arguments) {
      return '';
    }
    return toolCall.function.arguments;
  }

  private getParseErrorMessage(error: Object): string {
    const parseError = error as JsonParseErrorLike;
    return parseError.message || JSON.stringify(error);
  }

  private parseTaskType(taskType?: string): LlmTaskType {
    switch (taskType) {
      case 'concertTicket':
      case 'trainTicket':
      case 'redPacket':
      case 'taxi':
      case 'reminder':
        return taskType;
      default:
        return 'generic';
    }
  }

  private toTaskIdentificationResult(parsed: ParsedTaskResponse): LlmTaskIdentificationResult {
    const normalized = this.normalizeParsedTaskResponse(parsed);
    return {
      taskType: this.parseTaskType(normalized.taskType),
      title: normalized.title || '未知任务',
      ticketSaleStartTime: normalized.ticketSaleStartTime || normalized.timeText || '',
      performanceStartTime: normalized.performanceStartTime,
      priceRange: normalized.priceRange,
      ticketPlatform: normalized.ticketPlatform,
      city: normalized.city,
      venue: normalized.venue,
      lineup: normalized.lineup,
      otherInfo: normalized.otherInfo || normalized.extraInfo
    };
  }

  private normalizeParsedTaskResponse(parsed: ParsedTaskResponse): ParsedTaskResponse {
    const normalized: ParsedTaskResponse = {
      taskType: parsed.taskType,
      title: parsed.title || '',
      ticketSaleStartTime: this.normalizeChineseDateTime(parsed.ticketSaleStartTime || '') || parsed.timeText || '',
      performanceStartTime: this.normalizeDashedDateTime(parsed.performanceStartTime || ''),
      priceRange: parsed.priceRange || '',
      ticketPlatform: parsed.ticketPlatform || '',
      city: parsed.city || '',
      venue: parsed.venue || '',
      lineup: typeof parsed.lineup === 'string' ? parsed.lineup : '',
      otherInfo: parsed.otherInfo || parsed.extraInfo,
      timeText: parsed.timeText,
      extraInfo: parsed.extraInfo
    };
    if (!normalized.taskType && (normalized.title || normalized.ticketPlatform || normalized.venue)) {
      normalized.taskType = 'concertTicket';
    }
    return normalized;
  }

  private normalizeDashedDateTime(value: string): string {
    if (!value) {
      return '';
    }
    const normalized = value.trim().replace('T', ' ');
    const match = normalized.match(/(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})(?::(\d{2}))?/);
    if (!match) {
      return this.normalizeChineseDateTime(value);
    }
    return `${match[1].slice(2)}-${match[2]}-${match[3]} ${match[4]}:${match[5]}:${match[6] || '00'}`;
  }

  private normalizeChineseDateTime(value: string): string {
    if (!value) {
      return '';
    }
    const normalized = value.replace(/\s+/g, ' ').trim();
    const directMatch = normalized.match(/(\d{2})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})(?::(\d{2}))?/);
    if (directMatch) {
      return `${directMatch[1]}-${directMatch[2]}-${directMatch[3]} ${directMatch[4]}:${directMatch[5]}:${directMatch[6] || '00'}`;
    }
    const chineseMatch = normalized.match(/(?:(\d{4})年)?(\d{1,2})月(\d{1,2})日\s*(\d{1,2})[:：点时](\d{1,2})?/);
    if (!chineseMatch) {
      return normalized;
    }
    const fullYear = chineseMatch[1] ? Number(chineseMatch[1]) : 2026;
    const shortYear = `${fullYear}`.slice(2);
    const month = `${Number(chineseMatch[2])}`.padStart(2, '0');
    const day = `${Number(chineseMatch[3])}`.padStart(2, '0');
    const hour = `${Number(chineseMatch[4])}`.padStart(2, '0');
    const minute = `${Number(chineseMatch[5] || '0')}`.padStart(2, '0');
    return `${shortYear}-${month}-${day} ${hour}:${minute}:00`;
  }
}

export async function pixelMapToBase64(
  pixelMap: image.PixelMap,
  options?: PixelMapEncodeOptions
): Promise<string> {
  const encodeOptions: PixelMapEncodeOptions = options ? options : {
    format: 'image/jpeg',
    quality: 40
  };
  const imageInfo = getPixelMapInfo(pixelMap);
  const packer = image.createImagePacker();
  try {
    const arrayBuffer = await packer.packToData(pixelMap, encodeOptions);
    const uint8Array = new Uint8Array(arrayBuffer);
    const base64 = new util.Base64Helper().encodeToStringSync(uint8Array);
    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      'pixelMapToBase64 done size=%{public}s format=%{public}s quality=%{public}d packedBytes=%{public}d base64Chars=%{public}d',
      imageInfo,
      encodeOptions.format,
      encodeOptions.quality,
      uint8Array.length,
      base64.length
    );
    return base64;
  } finally {
    await packer.release();
  }
}

function getPixelMapInfo(pixelMap: image.PixelMap): string {
  try {
    const info = pixelMap.getImageInfoSync() as PixelMapInfoLike;
    if (info.size) {
      return `${info.size.width}x${info.size.height}`;
    }
    if (typeof info.width === 'number' && typeof info.height === 'number') {
      return `${info.width}x${info.height}`;
    }
  } catch (error) {
    hilog.warn(LOG_DOMAIN, LOG_TAG, 'getPixelMapInfo failed: %{public}s', JSON.stringify(error));
  }
  return 'unknown';
}
