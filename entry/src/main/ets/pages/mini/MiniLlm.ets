import { hilog } from '@kit.PerformanceAnalysisKit';
import image from '@ohos.multimedia.image';
import { LlmService, LlmTaskIdentificationResult, pixelMapToBase64 } from './MiniLlmService';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'Mini';

export type MiniTaskType = 'concertTicket' | 'trainTicket' | 'redPacket' | 'taxi' | 'reminder' | 'generic';

export interface EnhancedTaskResult {
  taskType: MiniTaskType;
  title: string;
  timeText: string;
  confidence: number;
  extraInfo?: string;
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
    hilog.error(LOG_DOMAIN, LOG_TAG, 'Task identification failed: %{public}s', JSON.stringify(error));
    return fallbackTaskIdentification(userText);
  }
}

function normalizeTaskResult(
  result: LlmTaskIdentificationResult,
  userText: string
): EnhancedTaskResult {
  let taskType = result.taskType;
  let title = result.title || '';
  let timeText = result.timeText || '';
  let confidence = result.confidence || 0.5;

  if (taskType === 'generic' && /演唱会|演出|抢票|开抢/.test(userText)) {
    taskType = 'concertTicket';
    confidence = Math.max(confidence, 0.72);
  }
  if (!title) {
    title = taskType === 'concertTicket' ? '抢演出票' : '通用任务';
  }

  return {
    taskType,
    title,
    timeText,
    confidence,
    extraInfo: result.extraInfo
  };
}

function fallbackTaskIdentification(userText: string): EnhancedTaskResult {
  const normalized = userText.toLowerCase();
  const taskType: MiniTaskType =
    normalized.includes('演出') || normalized.includes('演唱会') ? 'concertTicket' : 'generic';

  return {
    taskType,
    title: taskType === 'concertTicket' ? '抢演出票' : '通用任务',
    timeText: '',
    confidence: 0.6,
    extraInfo: '使用回退识别方式'
  };
}
