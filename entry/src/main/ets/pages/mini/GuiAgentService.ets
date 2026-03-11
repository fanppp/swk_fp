import componentUtils from '@ohos.arkui.componentUtils';

export type GuiSemanticRole = 'button' | 'input' | 'text';
export type GuiAgentActionType = 'click' | 'scroll' | 'none';

export interface GuiSemanticDescriptor {
  id: string;
  label: string;
  role: GuiSemanticRole;
  clickable: boolean;
  keywords?: string[];
}

export interface GuiRuntimeBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
  centerX: number;
  centerY: number;
  width: number;
  height: number;
}

export interface GuiRuntimeElement {
  id: string;
  label: string;
  role: GuiSemanticRole;
  clickable: boolean;
  keywords: string[];
  visible: boolean;
  bounds: GuiRuntimeBounds;
}

export interface GuiViewport {
  width: number;
  height: number;
}

export interface GuiPerceptionSnapshot {
  instruction: string;
  viewport: GuiViewport;
  elements: GuiRuntimeElement[];
}

export interface GuiActionPlan {
  action: GuiAgentActionType;
  reason: string;
  targetId?: string;
  targetLabel?: string;
  direction?: 'up' | 'down';
  x?: number;
  y?: number;
  snapshotText: string;
}

interface GuiScoredElement {
  element: GuiRuntimeElement;
  score: number;
}

export class GuiAgentService {
  captureSnapshot(
    instruction: string,
    descriptors: GuiSemanticDescriptor[],
    viewport: GuiViewport
  ): GuiPerceptionSnapshot {
    const elements: GuiRuntimeElement[] = [];
    descriptors.forEach((descriptor: GuiSemanticDescriptor) => {
      const resolved = this.resolveElement(descriptor, viewport);
      if (resolved !== undefined) {
        elements.push(resolved);
      }
    });

    return {
      instruction,
      viewport,
      elements
    };
  }

  planAction(snapshot: GuiPerceptionSnapshot): GuiActionPlan {
    const normalizedInstruction = snapshot.instruction.trim();
    const snapshotText = this.formatSnapshot(snapshot);
    if (!normalizedInstruction) {
      return {
        action: 'none',
        reason: '指令为空，无法规划动作',
        snapshotText
      };
    }

    const bestTarget = this.rankTargets(normalizedInstruction, snapshot.elements)[0];
    if (!bestTarget) {
      return {
        action: 'none',
        reason: '当前屏幕中没有匹配到可执行目标',
        snapshotText
      };
    }

    if (!bestTarget.visible) {
      return {
        action: 'scroll',
        reason: `已理解目标是「${bestTarget.label}」，但它当前不在可视区域，下一步应先滚动页面`,
        targetId: bestTarget.id,
        targetLabel: bestTarget.label,
        direction: bestTarget.bounds.centerY >= snapshot.viewport.height ? 'down' : 'up',
        snapshotText
      };
    }

    return {
      action: 'click',
      reason: `基于指令语义和屏幕元素匹配，选择「${bestTarget.label}」作为最优动作目标`,
      targetId: bestTarget.id,
      targetLabel: bestTarget.label,
      x: bestTarget.bounds.centerX,
      y: bestTarget.bounds.centerY,
      snapshotText
    };
  }

  private resolveElement(descriptor: GuiSemanticDescriptor, viewport: GuiViewport): GuiRuntimeElement | undefined {
    try {
      const info = componentUtils.getRectangleById(descriptor.id);
      const width = Number(info.size.width);
      const height = Number(info.size.height);
      const left = Number(info.screenOffset.x);
      const top = Number(info.screenOffset.y);
      if (width <= 0 || height <= 0) {
        return undefined;
      }

      return {
        id: descriptor.id,
        label: descriptor.label,
        role: descriptor.role,
        clickable: descriptor.clickable,
        keywords: descriptor.keywords ?? [],
        visible: this.isVisibleOnViewport(left, top, width, height, viewport),
        bounds: {
          left,
          top,
          right: left + width,
          bottom: top + height,
          centerX: Math.round(left + width / 2),
          centerY: Math.round(top + height / 2),
          width,
          height
        }
      };
    } catch (_error) {
      return undefined;
    }
  }

  private isVisibleOnViewport(
    left: number,
    top: number,
    width: number,
    height: number,
    viewport: GuiViewport
  ): boolean {
    const right = left + width;
    const bottom = top + height;
    return right > 0 && bottom > 0 && left < viewport.width && top < viewport.height;
  }

  private rankTargets(instruction: string, elements: GuiRuntimeElement[]): GuiRuntimeElement[] {
    const instructionTokens = this.tokenize(instruction);
    const scored: GuiScoredElement[] = [];
    elements.forEach((element: GuiRuntimeElement) => {
      if (!element.clickable) {
        return;
      }

      const item: GuiScoredElement = {
        element,
        score: this.scoreElement(instructionTokens, element)
      };
      if (item.score > 0) {
        scored.push(item);
      }
    });

    scored.sort((left: GuiScoredElement, right: GuiScoredElement) => right.score - left.score);
    const ranked: GuiRuntimeElement[] = [];
    scored.forEach((item: GuiScoredElement) => {
      ranked.push(item.element);
    });
    return ranked;
  }

  private scoreElement(tokens: string[], element: GuiRuntimeElement): number {
    let score = 0;
    const labelTokens = this.tokenize(element.label);
    const keywordTokens = element.keywords.flatMap((keyword: string) => this.tokenize(keyword));

    tokens.forEach((token: string) => {
      if (labelTokens.includes(token)) {
        score += 8;
      }
      if (keywordTokens.includes(token)) {
        score += 5;
      }
    });

    if (element.role === 'button') {
      score += 4;
    }
    if (element.label.includes('抢票')) {
      score += 10;
    }

    return score;
  }

  private tokenize(text: string): string[] {
    return text
      .replace(/[，。！？、,.!?\s]+/g, ' ')
      .split(' ')
      .map((token: string) => token.trim())
      .filter((token: string) => token.length > 0)
      .flatMap((token: string) => this.expandChineseToken(token));
  }

  private expandChineseToken(token: string): string[] {
    if (token.length <= 1) {
      return [token];
    }

    const expanded: string[] = [token];
    for (let index = 0; index < token.length; index++) {
      expanded.push(token.substring(index, index + 1));
    }
    return expanded;
  }

  private formatSnapshot(snapshot: GuiPerceptionSnapshot): string {
    const lines: string[] = [];
    lines.push(`instruction=${snapshot.instruction}`);
    snapshot.elements.forEach((element: GuiRuntimeElement) => {
      lines.push(
        `${element.role}:${element.label}#${element.id} ` +
        `bounds=(${element.bounds.left},${element.bounds.top},${element.bounds.right},${element.bounds.bottom}) ` +
        `center=(${element.bounds.centerX},${element.bounds.centerY}) clickable=${element.clickable} visible=${element.visible}`
      );
    });
    return lines.join('\n');
  }
}
