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
  timeText: string;
  confidence: number;
  extraInfo?: string;
}

export interface LlmMultimodalRequest {
  userText: string;
  imageBase64?: string;
  imageMimeType?: 'image/png' | 'image/jpeg';
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
}

interface LlmChoice {
  message?: LlmChoiceMessage;
}

interface LlmApiResponse {
  choices?: LlmChoice[];
}

interface ParsedTaskResponse {
  taskType?: string;
  title?: string;
  timeText?: string;
  confidence?: number;
  extraInfo?: string;
}

interface PixelMapEncodeOptions {
  format: 'image/png' | 'image/jpeg';
  quality: number;
}

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
      text: `用户指令：${request.userText}`
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
      text: `你是一个抢票任务识别助手。

请根据用户指令和截图识别任务，返回 JSON：
{
  "taskType": "concertTicket|trainTicket|redPacket|taxi|reminder|generic",
  "title": "任务标题",
  "timeText": "时间信息",
  "confidence": 0.0,
  "extraInfo": "可选附加信息"
}

规则：
- 演唱会、演出、抢票场景优先识别为 concertTicket
- 只输出 JSON，不要附带解释`
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
    try {
      const response = await httpRequest.request(`${LLM_CONFIG.baseUrl}/v1/chat/completions`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${LLM_CONFIG.apiKey}`
        },
        extraData: JSON.stringify({
          model: LLM_CONFIG.model,
          messages,
          temperature: 0.1,
          max_tokens: 1000
        }),
        expectDataType: http.HttpDataType.STRING
      });

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}: ${response.result}`);
      }

      const result = JSON.parse(response.result as string) as LlmApiResponse;
      const firstChoice = result.choices && result.choices.length > 0 ? result.choices[0] : undefined;
      const content = firstChoice && firstChoice.message && firstChoice.message.content ?
        firstChoice.message.content : '';
      if (!content) {
        throw new Error('No content in LLM response');
      }
      return content;
    } finally {
      httpRequest.destroy();
    }
  }

  private parseTaskIdentificationResponse(response: string): LlmTaskIdentificationResult {
    try {
      const jsonMatch = response.match(/\{[\s\S]*\}/);
      const parsed = JSON.parse(jsonMatch ? jsonMatch[0] : response) as ParsedTaskResponse;
      return {
        taskType: this.parseTaskType(parsed.taskType),
        title: parsed.title || '未知任务',
        timeText: parsed.timeText || '',
        confidence: parsed.confidence || 0.5,
        extraInfo: parsed.extraInfo
      };
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Parse response failed: %{public}s', JSON.stringify(error));
      return this.fallbackParseTaskIdentification(response);
    }
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

  private fallbackParseTaskIdentification(response: string): LlmTaskIdentificationResult {
    const normalized = response.toLowerCase();
    const isConcert = normalized.includes('演出') || normalized.includes('演唱会') || normalized.includes('抢票');
    return {
      taskType: isConcert ? 'concertTicket' : 'generic',
      title: isConcert ? '抢演出票' : '通用任务',
      timeText: '',
      confidence: 0.3,
      extraInfo: response.substring(0, 100)
    };
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

  const packer = image.createImagePacker();
  try {
    const arrayBuffer = await packer.packToData(pixelMap, encodeOptions);
    const uint8Array = new Uint8Array(arrayBuffer);
    return new util.Base64Helper().encodeToStringSync(uint8Array);
  } finally {
    await packer.release();
  }
}
