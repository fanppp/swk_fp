import { textRecognition } from '@kit.CoreVisionKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import image from '@ohos.multimedia.image';
import { LlmService, LlmMultimodalRequest, LlmTaskIdentificationResult, pixelMapToBase64 } from './MiniLlmService';
import { UiTreeService } from './MiniUiTreeService';
import { MiniTaskType } from './MiniTaskTypes';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'Mini';

let isTextRecognitionReady: boolean = false;

export interface LlmTimeResult {
  timeText: string;
  rawResponseText: string;
}

export interface EnhancedTaskResult {
  taskType: MiniTaskType;
  title: string;
  timeText: string;
  confidence: number;
  extraInfo?: string;
}

export interface IdentifyTaskOptions {
  includeUiTree?: boolean;
  imageMimeType?: 'image/png' | 'image/jpeg';
  imageQuality?: number;
  imageDetail?: 'low' | 'high' | 'auto';
}

/**
 * 增强的任务识别功能
 * 使用大模型来识别任务类型、标题和时间信息
 */
export async function identifyTaskFromUserInput(
  context: common.UIAbilityContext,
  userText: string,
  screenshotPixelMap?: image.PixelMap,
  options: IdentifyTaskOptions = {}
): Promise<EnhancedTaskResult> {
  hilog.info(LOG_DOMAIN, LOG_TAG, 'Starting enhanced task identification');

  try {
    const llmService = LlmService.getInstance();
    const includeUiTree = options.includeUiTree === true;

    // 准备请求数据
    const request: LlmMultimodalRequest = {
      userText: userText,
      imageMimeType: options.imageMimeType || 'image/jpeg',
      imageDetail: options.imageDetail || 'low'
    };

    // 获取UI组件树
    if (includeUiTree) {
      const uiTreeService = UiTreeService.getInstance();
      try {
        request.uiComponentTree = await uiTreeService.getSimplifiedUiInfo(context);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'UI tree captured successfully');
      } catch (error) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to capture UI tree: %{public}s', JSON.stringify(error));
      }
    }

    // 处理截图
    if (screenshotPixelMap) {
      try {
        request.imageBase64 = await pixelMapToBase64(screenshotPixelMap, {
          format: options.imageMimeType || 'image/jpeg',
          quality: options.imageQuality ?? 40
        });
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Screenshot processed successfully');
      } catch (error) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to process screenshot: %{public}s', JSON.stringify(error));
      }
    }

    // 调用大模型进行分析
    const result = await llmService.identifyTaskFromMultimodal(request);
    const normalizedResult = normalizeTaskResult(result, request.uiComponentTree, userText);

    hilog.info(
      LOG_DOMAIN,
      LOG_TAG,
      'Task identification completed: type=%{public}s, title=%{public}s, confidence=%{public}f',
      normalizedResult.taskType,
      normalizedResult.title,
      normalizedResult.confidence
    );

    return {
      taskType: normalizedResult.taskType as MiniTaskType,
      title: normalizedResult.title,
      timeText: normalizedResult.timeText,
      confidence: normalizedResult.confidence,
      extraInfo: normalizedResult.extraInfo
    };
  } catch (error) {
    hilog.error(LOG_DOMAIN, LOG_TAG, 'Enhanced task identification failed: %{public}s', JSON.stringify(error));

    // 回退到原始识别方式
    return await fallbackTaskIdentification(userText, screenshotPixelMap);
  }
}

function normalizeTaskResult(
  result: LlmTaskIdentificationResult,
  uiComponentTree: string | undefined,
  userText: string
): LlmTaskIdentificationResult {
  let taskType = result.taskType;
  let title = result.title || '';
  let timeText = result.timeText || '';
  let confidence = result.confidence || 0.5;

  const mergedText = `${userText}\n${uiComponentTree || ''}`;
  if (taskType === 'generic' && /演唱会|演出|抢票|开抢/.test(mergedText)) {
    taskType = 'concertTicket';
    confidence = Math.max(confidence, 0.72);
  }

  if ((!title || title === '未知任务' || title === '通用任务' || title === '抢演出票') && uiComponentTree) {
    const titleMatch = uiComponentTree.match(/\[([^\]]*演唱会[^\]]*)\]/);
    if (titleMatch && titleMatch[1]) {
      title = titleMatch[1];
    }
  }

  if (!timeText && uiComponentTree) {
    const timeMatch = uiComponentTree.match(/(\d{1,2}月\d{1,2}日\s*\d{1,2}:\d{2})|(\d{4}\.\d{2}\.\d{2}\s+\d{2}:\d{2})|(\d{1,2}:\d{2})/);
    if (timeMatch) {
      timeText = timeMatch[0];
    }
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

/**
 * 回退的任务识别（使用原有逻辑）
 */
async function fallbackTaskIdentification(
  userText: string,
  screenshotPixelMap?: image.PixelMap
): Promise<EnhancedTaskResult> {
  hilog.info(LOG_DOMAIN, LOG_TAG, 'Using fallback task identification');

  const normalized = userText.toLowerCase();

  let taskType: MiniTaskType = 'generic';
  let title = '通用任务';

  if (normalized.includes('演出') || normalized.includes('演唱会')) {
    taskType = 'concertTicket';
    title = '抢演出票';
  } else if (normalized.includes('火车票') || normalized.includes('高铁')) {
    taskType = 'trainTicket';
    title = '抢火车票';
  } else if (normalized.includes('红包')) {
    taskType = 'redPacket';
    title = '红包任务';
  } else if (normalized.includes('打车') || normalized.includes('约车')) {
    taskType = 'taxi';
    title = '打车任务';
  } else if (normalized.includes('提醒') || normalized.includes('闹钟')) {
    taskType = 'reminder';
    title = '提醒任务';
  }

  let timeText = '';

  // 尝试从截图中提取时间
  if (screenshotPixelMap) {
    try {
      const timeResult = await extractTaskTimeFromImageByLlm(screenshotPixelMap);
      timeText = timeResult.timeText;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Failed to extract time from image: %{public}s', JSON.stringify(error));
    }
  }

  // 如果没有从图片提取到时间，尝试从文本中提取
  if (!timeText) {
    const timeMatch = userText.match(/(\d{1,2})[:.点时](\d{1,2})/);
    timeText = timeMatch ? `${timeMatch[1].padStart(2, '0')}:${timeMatch[2].padStart(2, '0')}` : '';
  }

  return {
    taskType,
    title,
    timeText,
    confidence: 0.6,
    extraInfo: '使用回退识别方式'
  };
}

export async function understandTicketTaskByLlm(input: string): Promise<boolean> {
  hilog.info(LOG_DOMAIN, LOG_TAG, 'step1 send text to llm: %{public}s', input);
  const normalized = input.toLowerCase();
  const hasScene = normalized.includes('演唱会') || normalized.includes('演出');
  const hasTicket = normalized.includes('票') || normalized.includes('ticket') || normalized.includes('抢');
  const isMatched = hasScene && hasTicket;
  hilog.info(LOG_DOMAIN, LOG_TAG, 'step1 llm intent understood=%{public}s', isMatched ? '1' : '0');
  return isMatched;
}

export async function extractTaskTimeFromImageByLlm(pixelMap: image.PixelMap): Promise<LlmTimeResult> {
  hilog.info(LOG_DOMAIN, LOG_TAG, 'step3 send bottom-third screenshot to llm');
  const rawText = await recognizeByOcrModel(pixelMap);
  const timeText = extractTimeText(rawText);
  if (timeText.length === 0) {
    hilog.error(LOG_DOMAIN, LOG_TAG, 'step4 llm response has no valid time');
    throw new Error('llm response has no valid time');
  }
  hilog.info(
    LOG_DOMAIN,
    LOG_TAG,
    'step4 llm response parsed time=%{public}s rawLen=%{public}d',
    timeText,
    rawText.length
  );
  return {
    timeText,
    rawResponseText: rawText
  };
}

async function recognizeByOcrModel(pixelMap: image.PixelMap): Promise<string> {
  await ensureTextRecognitionReady();
  try {
    const result = await textRecognition.recognizeText(
      { pixelMap },
      { isDirectionDetectionSupported: true }

    );
    const recognized = result && result.value ? result.value : '';
    hilog.info(LOG_DOMAIN, LOG_TAG, 'step4 llm raw response length=%{public}d', recognized.length);
    return recognized;
  } catch (err) {
    hilog.error(LOG_DOMAIN, LOG_TAG, 'step4 llm call failed: %{public}s', JSON.stringify(err));
    throw new Error(JSON.stringify(err));
  }
}

async function ensureTextRecognitionReady(): Promise<void> {
  if (isTextRecognitionReady) {
    return;
  }
  const ready = await textRecognition.init();
  isTextRecognitionReady = ready;
  hilog.info(LOG_DOMAIN, LOG_TAG, 'step3 llm init ready=%{public}s', ready ? '1' : '0');
  if (!ready) {
    throw new Error('llm model init failed');
  }
}

function extractTimeText(text: string): string {
  const normalized = text.replace(/：/g, ':');
  const match = normalized.match(/(\d{1,2})\s*[:点时]\s*(\d{1,2}|半)?/);
  if (!match) {
    return '';
  }

  let hour = Number(match[1]);
  let minute = match[2] === '半' ? 30 : (match[2] ? Number(match[2]) : 0);
  const hasPmMark = text.includes('下午') || text.includes('晚上');
  if (hasPmMark && hour < 12) {
    hour += 12;
  }
  if (!Number.isFinite(hour) || hour < 0 || hour > 23) {
    return '';
  }
  if (!Number.isFinite(minute) || minute < 0 || minute > 59) {
    minute = 0;
  }

  const hourText = hour < 10 ? `0${hour}` : `${hour}`;
  const minuteText = minute < 10 ? `0${minute}` : `${minute}`;
  return `${hourText}:${minuteText}`;
}
