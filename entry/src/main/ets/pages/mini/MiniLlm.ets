import { hilog } from '@kit.PerformanceAnalysisKit';
import image from '@ohos.multimedia.image';
import { LlmService, LlmTaskIdentificationResult, pixelMapToBase64 } from './MiniLlmService';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'Mini';

export type MiniTaskType = 'concertTicket' | 'trainTicket' | 'redPacket' | 'taxi' | 'reminder' | 'generic';

export interface EnhancedTaskResult {
  taskType: MiniTaskType;
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

export async function identifyTaskFromUserInput(
  userText: string,
  screenshotPixelMap?: image.PixelMap
): Promise<EnhancedTaskResult> {
  try {
    const llmService = LlmService.getInstance();
    let imageBase64: string | undefined = undefined;
    if (screenshotPixelMap) {
      imageBase64 = await pixelMapToBase64(screenshotPixelMap, {
        format: 'image/jpeg',
        quality: 40
      });
    }
    const result = await llmService.identifyTaskFromMultimodal({
      userText,
      imageBase64,
      imageMimeType: 'image/jpeg',
      imageDetail: 'low'
    });
    return normalizeTaskResult(result, userText);
  } catch (error) {
    const errorMessage = (error as Error).message || JSON.stringify(error);
    hilog.error(LOG_DOMAIN, LOG_TAG, 'Task identification failed: %{public}s', errorMessage);
    throw new Error(errorMessage);
  }
}

function normalizeTaskResult(
  result: LlmTaskIdentificationResult,
  userText: string
): EnhancedTaskResult {
  let taskType = result.taskType;
  let title = result.title || '';
  let ticketSaleStartTime = result.ticketSaleStartTime || '';

  if (taskType === 'generic' && /演唱会|演出|抢票|开抢/.test(userText)) {
    taskType = 'concertTicket';
  }
  if (!title) {
    title = taskType === 'concertTicket' ? '抢演出票' : '通用任务';
  }

  return {
    taskType,
    title,
    ticketSaleStartTime,
    performanceStartTime: result.performanceStartTime,
    priceRange: result.priceRange,
    ticketPlatform: result.ticketPlatform,
    city: result.city,
    venue: result.venue,
    lineup: result.lineup,
    otherInfo: result.otherInfo
  };
}
