import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import image from '@ohos.multimedia.image';

interface SnapshotWindowLike {
  snapshot?: () => Promise<Object>;
  snapshotSync?: () => Object;
}

interface ImageInfoSize {
  width: number;
  height: number;
}

interface ImageInfoLike {
  width?: number;
  height?: number;
  size?: ImageInfoSize;
}

interface PixelMapLike {
  cropSync?: (region: CropRegion) => void;
  crop?: (region: CropRegion) => Promise<void>;
  getImageInfoSync?: () => ImageInfoLike;
  getImageInfo?: () => Promise<ImageInfoLike>;
}

interface CropRegion {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface PixelMapSize {
  width: number;
  height: number;
}

export interface MiniImageAttachment {
  name: string;
  mimeType: string;
  pixelMap: image.PixelMap;
}

export async function captureBottomHalfScreenshot(context: common.UIAbilityContext): Promise<MiniImageAttachment> {
  const hostWindow = await window.getLastWindow(context) as Object as SnapshotWindowLike;
  const snapshot = await takeWindowSnapshot(hostWindow);
  if (!snapshot) {
    throw new Error('snapshot failed');
  }
  await cropBottomHalf(snapshot as Object as PixelMapLike);

  const attachment: MiniImageAttachment = {
    name: `ticket_${Date.now()}.png`,
    mimeType: 'image/png',
    pixelMap: snapshot as image.PixelMap
  };
  return attachment;
}

async function takeWindowSnapshot(hostWindow: SnapshotWindowLike): Promise<Object | undefined> {
  if (hostWindow.snapshot) {
    return hostWindow.snapshot();
  }
  if (hostWindow.snapshotSync) {
    return hostWindow.snapshotSync();
  }
  return undefined;
}

async function cropBottomHalf(pixelMap: PixelMapLike): Promise<void> {
  const size = await getPixelMapSize(pixelMap);
  if (!size) {
    return;
  }

  const cropY = Math.floor(size.height / 2);
  const region: CropRegion = {
    x: 0,
    y: cropY,
    width: size.width,
    height: Math.max(1, size.height - cropY)
  };

  if (pixelMap.cropSync) {
    pixelMap.cropSync(region);
    return;
  }
  if (pixelMap.crop) {
    await pixelMap.crop(region);
  }
}

async function getPixelMapSize(pixelMap: PixelMapLike): Promise<PixelMapSize | undefined> {
  let info: ImageInfoLike | undefined = undefined;
  if (pixelMap.getImageInfoSync) {
    info = pixelMap.getImageInfoSync();
  } else if (pixelMap.getImageInfo) {
    info = await pixelMap.getImageInfo();
  }
  if (!info) {
    return undefined;
  }
  if (info.size) {
    const fromSize: PixelMapSize = {
      width: info.size.width,
      height: info.size.height
    };
    return fromSize;
  }
  if (typeof info.width === 'number' && typeof info.height === 'number') {
    const fromPlain: PixelMapSize = {
      width: info.width,
      height: info.height
    };
    return fromPlain;
  }
  return undefined;
}
