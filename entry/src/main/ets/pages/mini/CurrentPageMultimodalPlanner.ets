import { textRecognition } from '@kit.CoreVisionKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import http from '@ohos.net.http';
import image from '@ohos.multimedia.image';
import { GuiActionPlan, GuiPerceptionSnapshot } from './GuiAgentService';
import { captureFullScreenshot, pixelMapToCompressedBase64 } from './MiniVision';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'CurrentPagePlanner';
const MODEL_LOG_TAG: string = 'GuiAgentModel';

interface LlmConfig {
  baseUrl: string;
  apiKey: string;
  model: string;
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

interface LlmRequestBody {
  model: string;
  messages: LlmMessage[];
  temperature: number;
  max_tokens: number;
}

interface LlmChoiceMessage {
  content: string;
}

interface LlmChoice {
  message: LlmChoiceMessage;
}

interface LlmApiResponse {
  choices: LlmChoice[];
}

interface ParsedPlannerResult {
  action?: 'click' | 'scroll' | 'none';
  targetId?: string;
  targetLabel?: string;
  direction?: 'up' | 'down';
  reason?: string;
}

interface OcrVisibilityCheck {
  visible: boolean;
  matchedText: string;
}

interface PlannerInputPayload {
  compactUiTree: string;
  ocrText: string;
  includeImage: boolean;
  imageBase64?: string;
}

const LLM_CONFIG: LlmConfig = {
  baseUrl: 'https://api.v3.cm',
  apiKey: 'sk-mqIx6VohpghY3Fe26a070dE4775841D7BcFc7b073c2a0257',
  model: 'gpt-5.4'
};

let isTextRecognitionReady: boolean = false;

export class CurrentPageMultimodalPlanner {
  async planNextAction(
    context: common.UIAbilityContext,
    snapshot: GuiPerceptionSnapshot,
    fallbackPlan: GuiActionPlan
  ): Promise<GuiActionPlan> {
    const pixelMap = await captureFullScreenshot(context);
    const ocrText = await this.recognizeText(pixelMap);
    const plannerInput = await this.buildPlannerInput(pixelMap, snapshot, ocrText);
    const snapshotText = `${plannerInput.compactUiTree}\nocr=${plannerInput.ocrText}`;
    const ocrVisibility = this.checkTargetVisibilityByOcr(snapshot, ocrText);
    hilog.info(LOG_DOMAIN, MODEL_LOG_TAG, 'input includeImage=%{public}s ocrLen=%{public}d uiLen=%{public}d',
      plannerInput.includeImage ? '1' : '0', plannerInput.ocrText.length, plannerInput.compactUiTree.length);

    if (!ocrVisibility.visible) {
      hilog.info(LOG_DOMAIN, MODEL_LOG_TAG, 'plan scroll reason=ocr_target_missing target=%{public}s',
        fallbackPlan.targetLabel || ocrVisibility.matchedText || '目标按钮');
      return {
        action: 'scroll',
        reason: `OCR 未在当前截图中识别到目标文案，下一步应先滚动页面继续查找`,
        targetId: fallbackPlan.targetId,
        targetLabel: fallbackPlan.targetLabel || ocrVisibility.matchedText || '目标按钮',
        direction: this.inferScrollDirection(snapshot, fallbackPlan),
        snapshotText
      };
    }

    try {
      const response = await this.callLlmApi(snapshot.instruction, plannerInput);
      const parsed = this.parsePlannerResult(response, snapshot);
      parsed.snapshotText = snapshotText;
      hilog.info(
        LOG_DOMAIN,
        MODEL_LOG_TAG,
        'plan %{public}s target=%{public}s reason=%{public}s',
        parsed.action,
        parsed.targetLabel || parsed.targetId || 'none',
        parsed.reason
      );
      return parsed;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Planner fallback: %{public}s', JSON.stringify(error));
      hilog.warn(LOG_DOMAIN, MODEL_LOG_TAG, 'plan fallback action=%{public}s target=%{public}s',
        fallbackPlan.action, fallbackPlan.targetLabel || fallbackPlan.targetId || 'none');
      return {
        action: fallbackPlan.action,
        reason: `${fallbackPlan.reason}（LLM 失败，回退到本地规划）`,
        targetId: fallbackPlan.targetId,
        targetLabel: fallbackPlan.targetLabel,
        direction: fallbackPlan.direction,
        x: fallbackPlan.x,
        y: fallbackPlan.y,
        snapshotText
      };
    }
  }

  private async buildPlannerInput(
    pixelMap: image.PixelMap,
    snapshot: GuiPerceptionSnapshot,
    ocrText: string
  ): Promise<PlannerInputPayload> {
    const compactUiTree = this.buildCompactUiTree(snapshot);
    const includeImage = this.shouldIncludeImage(snapshot, ocrText);
    const payload: PlannerInputPayload = {
      compactUiTree,
      ocrText: this.compressOcrText(ocrText),
      includeImage
    };
    if (includeImage) {
      payload.imageBase64 = await pixelMapToCompressedBase64(pixelMap, 35);
    }
    return payload;
  }

  private buildCompactUiTree(snapshot: GuiPerceptionSnapshot): string {
    const lines: string[] = [];
    lines.push(`viewport=(${snapshot.viewport.width},${snapshot.viewport.height})`);
    snapshot.elements
      .filter((element) => element.clickable || this.isInstructionRelevant(snapshot.instruction, element.label, element.keywords))
      .forEach((element) => {
        lines.push(
          `id=${element.id};label=${element.label};role=${element.role};clickable=${element.clickable};visible=${element.visible};` +
          `bounds=${element.bounds.left},${element.bounds.top},${element.bounds.right},${element.bounds.bottom};` +
          `center=${element.bounds.centerX},${element.bounds.centerY}`
        );
      });
    return lines.join('\n');
  }

  private compressOcrText(ocrText: string): string {
    const normalized = ocrText.replace(/\s+/g, ' ').trim();
    if (normalized.length <= 180) {
      return normalized;
    }
    return normalized.substring(0, 180);
  }

  private shouldIncludeImage(snapshot: GuiPerceptionSnapshot, ocrText: string): boolean {
    if (ocrText.trim().length === 0) {
      return true;
    }
    const relevant = this.extractTargetKeywords(snapshot);
    return !relevant.some((keyword: string) => ocrText.includes(keyword));
  }

  private checkTargetVisibilityByOcr(snapshot: GuiPerceptionSnapshot, ocrText: string): OcrVisibilityCheck {
    const normalizedOcr = ocrText.replace(/\s+/g, '');
    const targets = this.extractTargetKeywords(snapshot);
    for (const target of targets) {
      if (target.length > 0 && normalizedOcr.includes(target)) {
        return { visible: true, matchedText: target };
      }
    }
    return { visible: false, matchedText: targets.length > 0 ? targets[0] : '' };
  }

  private extractTargetKeywords(snapshot: GuiPerceptionSnapshot): string[] {
    const keywords: string[] = [];
    snapshot.elements.forEach((element) => {
      if (!element.clickable) {
        return;
      }
      if (this.isInstructionRelevant(snapshot.instruction, element.label, element.keywords)) {
        keywords.push(element.label.replace(/\s+/g, ''));
        element.keywords.forEach((keyword: string) => {
          keywords.push(keyword.replace(/\s+/g, ''));
        });
      }
    });
    return Array.from(new Set(keywords));
  }

  private isInstructionRelevant(instruction: string, label: string, keywords: string[]): boolean {
    if (instruction.includes(label)) {
      return true;
    }
    return keywords.some((keyword: string) => instruction.includes(keyword));
  }

  private inferScrollDirection(snapshot: GuiPerceptionSnapshot, fallbackPlan: GuiActionPlan): 'up' | 'down' {
    if (fallbackPlan.direction) {
      return fallbackPlan.direction;
    }
    const target = snapshot.elements.find((item) => item.id === fallbackPlan.targetId);
    if (target && target.bounds.centerY < snapshot.viewport.height / 2) {
      return 'up';
    }
    return 'down';
  }

  private async recognizeText(pixelMap: image.PixelMap): Promise<string> {
    await this.ensureTextRecognitionReady();
    try {
      const result = await textRecognition.recognizeText(
        { pixelMap },
        { isDirectionDetectionSupported: true }
      );
      return result && result.value ? result.value : '';
    } catch (_error) {
      return '';
    }
  }

  private async ensureTextRecognitionReady(): Promise<void> {
    if (isTextRecognitionReady) {
      return;
    }
    isTextRecognitionReady = await textRecognition.init();
  }

  private async callLlmApi(
    instruction: string,
    plannerInput: PlannerInputPayload
  ): Promise<string> {
    const userContent: LlmMessageContent[] = [
      {
        type: 'text',
        text: `用户指令：${instruction}\n当前页面候选UI树与OCR：\n${plannerInput.compactUiTree}\nocr=${plannerInput.ocrText}`
      }
    ];
    if (plannerInput.includeImage && plannerInput.imageBase64) {
      userContent.push({
        type: 'image_url',
        image_url: {
          url: `data:image/jpeg;base64,${plannerInput.imageBase64}`,
          detail: 'low'
        }
      });
    }

    const requestBody: LlmRequestBody = {
      model: LLM_CONFIG.model,
      messages: [
        {
          role: 'system',
          content: [{
            type: 'text',
            text: `你是当前页面 GUI Agent 规划器。你只能基于当前页面截图、OCR 和 UI 树决定下一步操作。

输出 JSON：
{
  "action": "click|scroll|none",
  "targetId": "可选",
  "targetLabel": "可选",
  "direction": "up|down",
  "reason": "原因"
}

规则：
- 如果目标按钮当前 visible=true，输出 click
- 如果目标按钮不在当前可视区域，输出 scroll
- 不要假设点击已经成功
- 只输出 JSON`
          }]
        },
        {
          role: 'user',
          content: userContent
        }
      ],
      temperature: 0.1,
      max_tokens: 300
    };

    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(`${LLM_CONFIG.baseUrl}/v1/chat/completions`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${LLM_CONFIG.apiKey}`
        },
        extraData: JSON.stringify(requestBody),
        expectDataType: http.HttpDataType.STRING
      });

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      const result = JSON.parse(response.result as string) as LlmApiResponse;
      if (!result.choices || result.choices.length === 0) {
        throw new Error('empty llm response');
      }
      return result.choices[0].message.content;
    } finally {
      httpRequest.destroy();
    }
  }

  private parsePlannerResult(response: string, snapshot: GuiPerceptionSnapshot): GuiActionPlan {
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    const jsonStr = jsonMatch ? jsonMatch[0] : response;
    const parsed = JSON.parse(jsonStr) as ParsedPlannerResult;

    if (parsed.action === 'scroll') {
      return {
        action: 'scroll',
        reason: parsed.reason || '目标暂不可见，建议先滚动',
        targetId: parsed.targetId,
        targetLabel: parsed.targetLabel,
        direction: parsed.direction === 'up' ? 'up' : 'down',
        snapshotText: ''
      };
    }

    if (parsed.action === 'click' && parsed.targetId) {
      const target = snapshot.elements.find((item) => item.id === parsed.targetId);
      if (target && target.visible) {
        return {
          action: 'click',
          reason: parsed.reason || `点击${target.label}`,
          targetId: target.id,
          targetLabel: target.label,
          x: target.bounds.centerX,
          y: target.bounds.centerY,
          snapshotText: ''
        };
      }
    }

    return {
      action: 'none',
      reason: parsed.reason || '当前无法确定可执行动作',
      snapshotText: ''
    };
  }
}
