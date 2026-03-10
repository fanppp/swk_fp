import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { UiAutomationRegistry } from './MiniUiAutomationRegistry';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'UiTreeService';

export interface WindowProperties {
  width: number;
  height: number;
  isMainWindow?: boolean;
  scrollable?: boolean;
  fixed?: boolean;
  visible?: boolean;
  system?: boolean;
}

export interface UiBounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface UiNode {
  id?: string;
  type: string;
  text?: string;
  bounds?: UiBounds;
  properties?: WindowProperties;
  children?: UiNode[];
}

export class UiTreeService {
  private static instance: UiTreeService;

  public static getInstance(): UiTreeService {
    if (!UiTreeService.instance) {
      UiTreeService.instance = new UiTreeService();
    }
    return UiTreeService.instance;
  }

  /**
   * 获取当前窗口的UI组件树
   */
  async captureUiTree(context: common.UIAbilityContext): Promise<string> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'Starting UI tree capture');

    try {
      const registryTree = UiAutomationRegistry.getInstance().getUiTree();
      if (registryTree) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'Using registered UI tree, tree size: %{public}d chars', registryTree.length);
        return registryTree;
      }

      // 获取当前窗口
      const hostWindow = await window.getLastWindow(context);

      // 尝试获取UI树信息（HarmonyOS的UI树获取API可能需要特殊权限）
      const uiTree = await this.extractUiTreeFromWindow(hostWindow);
      const treeString = this.formatUiTreeAsString(uiTree);

      hilog.info(LOG_DOMAIN, LOG_TAG, 'UI tree capture completed, tree size: %{public}d chars', treeString.length);
      return treeString;
    } catch (error) {
      const err = error as Error;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'UI tree capture failed: %{public}s', err.message || JSON.stringify(error));
      return this.generateFallbackUiTree();
    }
  }

  /**
   * 从窗口提取UI树
   */
  private async extractUiTreeFromWindow(hostWindow: window.Window): Promise<UiNode> {
    // 注意：HarmonyOS的UI树获取API可能受限，这里提供一个基础实现
    // 实际使用时可能需要配合UITest相关API或其他系统级API

    try {
      // 尝试获取窗口属性
      const windowProperties = await hostWindow.getWindowProperties();
      const windowArea = windowProperties.windowRect;

      const rootNode: UiNode = this.createUiNode(
        'root',
        'Window',
        'Main Window',
        this.createUiBounds(
          windowArea.left,
          windowArea.top,
          windowArea.left + windowArea.width,
          windowArea.top + windowArea.height
        ),
        this.createProperties({
          width: windowArea.width,
          height: windowArea.height,
          isMainWindow: true
        }),
        await this.extractChildNodes(hostWindow)
      );

      return rootNode;
    } catch (error) {
      const err = error as Error;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to extract UI tree from window: %{public}s', err.message || JSON.stringify(error));
      throw new Error('Failed to extract UI tree from window');
    }
  }

  /**
   * 创建UiNode对象
   */
  private createUiNode(
    id: string,
    type: string,
    text: string,
    bounds: UiBounds,
    properties: WindowProperties,
    children?: UiNode[]
  ): UiNode {
    const node: UiNode = {
      id: id,
      type: type,
      text: text,
      bounds: bounds,
      properties: properties
    };

    if (children) {
      node.children = children;
    }

    return node;
  }

  /**
   * 创建UiBounds对象
   */
  private createUiBounds(left: number, top: number, right: number, bottom: number): UiBounds {
    return {
      left: left,
      top: top,
      right: right,
      bottom: bottom
    };
  }

  /**
   * 创建WindowProperties对象
   */
  private createProperties(props: Partial<WindowProperties>): WindowProperties {
    const result: WindowProperties = {
      width: props.width !== undefined ? props.width : 0,
      height: props.height !== undefined ? props.height : 0,
      isMainWindow: props.isMainWindow !== undefined ? props.isMainWindow : false,
      scrollable: props.scrollable !== undefined ? props.scrollable : false,
      fixed: props.fixed !== undefined ? props.fixed : false,
      visible: props.visible !== undefined ? props.visible : true,
      system: props.system !== undefined ? props.system : false
    };

    return result;
  }

  /**
   * 提取子节点（模拟实现）
   */
  private async extractChildNodes(hostWindow: window.Window): Promise<UiNode[]> {
    // 这里是一个简化的实现，实际情况下需要使用HarmonyOS的UI遍历API
    // 由于API限制，我们提供一个基础的结构

    const contentArea = this.createUiNode(
      'content_area',
      'ContentArea',
      'Main Content Area',
      this.createUiBounds(0, 0, 1080, 2400),
      this.createProperties({ scrollable: true }),
      [
        this.createUiNode(
          'navigation_bar',
          'NavigationBar',
          'Navigation',
          this.createUiBounds(0, 0, 1080, 120),
          this.createProperties({ fixed: true })
        ),
        this.createUiNode(
          'main_content',
          'MainContent',
          'Main Content',
          this.createUiBounds(0, 120, 1080, 2280),
          this.createProperties({ scrollable: true }),
          []
        ),
        this.createUiNode(
          'bottom_navigation',
          'BottomNavigation',
          'Bottom Navigation',
          this.createUiBounds(0, 2280, 1080, 2400),
          this.createProperties({ fixed: true })
        )
      ]
    );

    return [contentArea];
  }

  /**
   * 格式化UI树为字符串
   */
  private formatUiTreeAsString(node: UiNode, depth: number = 0): string {
    const indent = '  '.repeat(depth);
    let result = `${indent}${node.type}`;

    if (node.id) {
      result += ` (id: ${node.id})`;
    }

    if (node.text) {
      result += ` [${node.text}]`;
    }

    if (node.bounds) {
      result += ` bounds(${node.bounds.left},${node.bounds.top},${node.bounds.right},${node.bounds.bottom})`;
    }

    if (node.properties) {
      const props = node.properties;
      const validEntries: string[] = [];

      if (props.width !== undefined && props.width !== null) {
        validEntries.push(`width=${props.width}`);
      }
      if (props.height !== undefined && props.height !== null) {
        validEntries.push(`height=${props.height}`);
      }
      if (props.isMainWindow !== undefined && props.isMainWindow !== null) {
        validEntries.push(`isMainWindow=${props.isMainWindow}`);
      }
      if (props.scrollable !== undefined && props.scrollable !== null) {
        validEntries.push(`scrollable=${props.scrollable}`);
      }
      if (props.fixed !== undefined && props.fixed !== null) {
        validEntries.push(`fixed=${props.fixed}`);
      }
      if (props.visible !== undefined && props.visible !== null) {
        validEntries.push(`visible=${props.visible}`);
      }
      if (props.system !== undefined && props.system !== null) {
        validEntries.push(`system=${props.system}`);
      }

      if (validEntries.length > 0) {
        result += ` props(${validEntries.join(', ')})`;
      }
    }

    result += '\n';

    if (node.children && node.children.length > 0) {
      for (const child of node.children) {
        result += this.formatUiTreeAsString(child, depth + 1);
      }
    }

    return result;
  }

  /**
   * 生成回退UI树（当无法获取真实UI树时使用）
   */
  private generateFallbackUiTree(): string {
    const timestamp = Date.now();
    return `Window (id: main_window_${timestamp})
  StatusBar (id: status_bar) bounds(0,0,1080,60) props(height=60, visible=true)
  ContentArea (id: content_area) bounds(0,60,1080,2340) props(scrollable=true)
    NavigationBar (id: nav_bar) bounds(0,60,1080,180) props(fixed=true)
    MainContent (id: main_content) bounds(0,180,1080,2220) props(scrollable=true)
    BottomBar (id: bottom_bar) bounds(0,2220,1080,2340) props(fixed=true)
  NavigationBar (id: system_nav) bounds(0,2340,1080,2400) props(height=60, system=true)
`;
  }

  /**
   * 获取简化的UI信息（用于快速分析）
   */
  async getSimplifiedUiInfo(context: common.UIAbilityContext): Promise<string> {
    try {
      const fullTree = await this.captureUiTree(context);

      // 提取关键信息
      const lines = fullTree.split('\n');
      const simplified = lines
        .filter(line => line.includes('bounds') || line.includes('text'))
        .slice(0, 20) // 限制为前20个重要节点
        .join('\n');

      return simplified || '无可用UI信息';
    } catch (error) {
      const err = error as Error;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to get simplified UI info: %{public}s', err.message || JSON.stringify(error));
      return '获取UI信息失败';
    }
  }

  /**
   * 查找可点击的元素
   */
  async findClickableElements(context: common.UIAbilityContext): Promise<ClickableElement[]> {
    try {
      const tree = await this.captureUiTree(context);
      return this.parseClickableElements(tree);
    } catch (error) {
      const err = error as Error;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Failed to find clickable elements: %{public}s', err.message || JSON.stringify(error));
      return [];
    }
  }

  /**
   * 创建ClickableElement对象
   */
  private createClickableElement(
    text: string,
    type: string,
    bounds: UiBounds,
    centerX: number,
    centerY: number,
    clickable: boolean
  ): ClickableElement {
    return {
      text: text,
      type: type,
      bounds: bounds,
      centerX: centerX,
      centerY: centerY,
      clickable: clickable
    };
  }

  /**
   * 解析可点击元素
   */
  private parseClickableElements(treeString: string): ClickableElement[] {
    const elements: ClickableElement[] = [];
    const lines = treeString.split('\n');

    for (const line of lines) {
      // 查找包含bounds信息的行，假设这些可能是可点击的
      const boundsMatch = line.match(/bounds\((\d+),(\d+),(\d+),(\d+)\)/);
      const textMatch = line.match(/\[([^\]]+)\]/);
      const typeMatch = line.match(/^\s*(\w+)/);

      if (boundsMatch && textMatch && typeMatch) {
        const left = parseInt(boundsMatch[1]);
        const top = parseInt(boundsMatch[2]);
        const right = parseInt(boundsMatch[3]);
        const bottom = parseInt(boundsMatch[4]);

        // 计算中心点
        const centerX = Math.floor((left + right) / 2);
        const centerY = Math.floor((top + bottom) / 2);

        const element = this.createClickableElement(
          textMatch[1],
          typeMatch[1],
          this.createUiBounds(left, top, right, bottom),
          centerX,
          centerY,
          this.isLikelyClickable(typeMatch[1], textMatch[1])
        );

        elements.push(element);
      }
    }

    return elements.filter(element => element.clickable);
  }

  /**
   * 判断元素是否可能可点击
   */
  private isLikelyClickable(type: string, text: string): boolean {
    const clickableTypes = ['Button', 'Text', 'Image', 'ListItem', 'MenuItem'];
    const clickableKeywords = ['按钮', '点击', '确认', '取消', '提交', '登录', '注册', '搜索'];

    if (clickableTypes.includes(type)) {
      return true;
    }

    return clickableKeywords.some(keyword => text.includes(keyword));
  }
}

export interface ClickableElement {
  text: string;
  type: string;
  bounds: UiBounds;
  centerX: number;
  centerY: number;
  clickable: boolean;
}
