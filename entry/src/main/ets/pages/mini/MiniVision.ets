import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import image from '@ohos.multimedia.image';
import fileIo from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import photoAccessHelper from '@ohos.file.photoAccessHelper';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'Mini';

interface SnapshotWindowLike {
  snapshot?: () => Promise<Object>;
  snapshotSync?: () => Object;
}

interface PixelMapLike {
  cropSync?: (region: Object) => void;
  crop?: (region: Object) => Promise<void>;
  getImageInfoSync?: () => ImageInfoLike;
  getImageInfo?: () => Promise<ImageInfoLike>;
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

interface CropRegionSize {
  width: number;
  height: number;
}

interface CropRegionWithSize {
  x: number;
  y: number;
  size: CropRegionSize;
}

interface CropRegionFlat {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface PixelMapSize {
  width: number;
  height: number;
}

interface CropMetadata {
  cropRegion: string;
  cropResult: string;
}

export interface MiniImageAttachment {
  name: string;
  mimeType: string;
  pixelMap: image.PixelMap;
  metadata?: Object;
}

export async function captureFullScreenshot(
  context: common.UIAbilityContext
): Promise<MiniImageAttachment> {
  hilog.info(LOG_DOMAIN, LOG_TAG, 'step2 start full screenshot');
  const hostWindow = await window.getLastWindow(context) as Object as SnapshotWindowLike;
  const snapshot = await takeWindowSnapshot(hostWindow);
  if (!snapshot) {
    throw new Error('snapshot failed');
  }

  hilog.info(LOG_DOMAIN, LOG_TAG, 'step2 full screenshot complete');
  const metadata: CropMetadata = {
    cropRegion: 'full_screen',
    cropResult: 'success'
  };
  const attachment: MiniImageAttachment = {
    name: `full_${Date.now()}.png`,
    mimeType: 'image/png',
    pixelMap: snapshot as image.PixelMap,
    metadata
  };
  return attachment;
}

export async function captureBottomThirdScreenshot(
  context: common.UIAbilityContext
): Promise<MiniImageAttachment> {
  hilog.info(LOG_DOMAIN, LOG_TAG, 'step2 start screenshot and crop bottom one-third');
  const hostWindow = await window.getLastWindow(context) as Object as SnapshotWindowLike;
  const snapshot = await takeWindowSnapshot(hostWindow);
  if (!snapshot) {
    throw new Error('snapshot failed');
  }

  const cropResult = await cropBottomThird(snapshot as Object as PixelMapLike);
  hilog.info(
    LOG_DOMAIN,
    LOG_TAG,
    'step2 screenshot complete, cropped=%{public}s',
    cropResult ? '1' : '0'
  );
  const metadata: CropMetadata = {
    cropRegion: 'bottom_third',
    cropResult: cropResult ? 'success' : 'failed'
  };
  const attachment: MiniImageAttachment = {
    name: `ticket_${Date.now()}.png`,
    mimeType: 'image/png',
    pixelMap: snapshot as image.PixelMap,
    metadata
  };
  return attachment;

}

export async function saveScreenshotToGallery(
  context: common.UIAbilityContext,
  pixelMap: image.PixelMap
): Promise<string> {
  const helper = photoAccessHelper.getPhotoAccessHelper(context);
  const fileStamp = Date.now();
  const backupDir = `${context.filesDir}/screenshots`;
  const backupPath = `${backupDir}/screenshot_${fileStamp}.png`;
  const backupUri = fileUri.getUriFromPath(backupPath);
  hilog.info(LOG_DOMAIN, LOG_TAG, 'step2 gallery source file path: %{public}s', backupPath);

  let file: fileIo.File | undefined = undefined;
  const packer = image.createImagePacker();
  try {
    const packedData = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 });
    const openMode = fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC;
    await ensureDirExists(backupDir);
    file = await fileIo.open(backupPath, openMode);
    await fileIo.write(file.fd, packedData);
  } finally {
    if (file) {
      await fileIo.close(file);
    }
    await packer.release();
  }

  // 创建相册资源配置
  const creationConfig: photoAccessHelper.PhotoCreationConfig = {
    title: `Screenshot_${fileStamp}`,
    fileNameExtension: 'png',
    photoType: photoAccessHelper.PhotoType.IMAGE
  };

  try {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'step2 creating photo in gallery via dialog');
    const createdUris = await helper.showAssetsCreationDialog([backupUri], [creationConfig]);
    if (createdUris && createdUris.length > 0) {
      const galleryUri = createdUris[0];
      hilog.info(LOG_DOMAIN, LOG_TAG, 'step2 screenshot saved via dialog: %{public}s', galleryUri);
      return `${galleryUri} | backup=${backupPath}`;
    }
    throw new Error('No URI returned from dialog');
  } catch (dialogError) {
    hilog.error(LOG_DOMAIN, LOG_TAG, 'Dialog save failed, fallback to backup file only: %{public}s', JSON.stringify(dialogError));
    return `backup-only=${backupPath}`;
  }
}

async function ensureDirExists(path: string): Promise<void> {
  try {
    await fileIo.mkdir(path);
  } catch (_error) {
  }
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

async function cropBottomThird(pixelMap: PixelMapLike): Promise<boolean> {
  const size = await getPixelMapSize(pixelMap);
  if (!size) {
    return false;
  }

  const cropY = Math.floor(size.height * 2 / 3);
  const cropHeight = Math.max(1, size.height - cropY);
  hilog.info(
    LOG_DOMAIN,
    LOG_TAG,
    'step2 crop params width=%{public}d height=%{public}d cropY=%{public}d cropHeight=%{public}d',
    size.width,
    size.height,
    cropY,
    cropHeight
  );
  const regionSize: CropRegionSize = {
    width: size.width,
    height: cropHeight
  };
  const regionWithSize: CropRegionWithSize = {
    x: 0,
    y: cropY,
    size: regionSize
  };
  const regionFlat: CropRegionFlat = {
    x: 0,
    y: cropY,
    width: size.width,
    height: cropHeight
  };

  if (tryCropSync(pixelMap, regionWithSize) || tryCropSync(pixelMap, regionFlat)) {
    return true;
  }
  if (await tryCropAsync(pixelMap, regionWithSize) || await tryCropAsync(pixelMap, regionFlat)) {
    return true;
  }
  return false;
}

function tryCropSync(pixelMap: PixelMapLike, region: Object): boolean {
  if (!pixelMap.cropSync) {
    return false;
  }
  try {
    pixelMap.cropSync(region);
    return true;
  } catch (_err) {
    return false;
  }
}

async function tryCropAsync(pixelMap: PixelMapLike, region: Object): Promise<boolean> {
  if (!pixelMap.crop) {
    return false;
  }
  try {
    await pixelMap.crop(region);
    return true;
  } catch (_err) {
    return false;
  }
}

async function getPixelMapSize(pixelMap: PixelMapLike): Promise<PixelMapSize | undefined> {
  if (pixelMap.getImageInfoSync) {
    return parseImageInfo(pixelMap.getImageInfoSync());
  }
  if (pixelMap.getImageInfo) {
    return parseImageInfo(await pixelMap.getImageInfo());
  }
  return undefined;
}

function parseImageInfo(info: ImageInfoLike): PixelMapSize | undefined {
  if (info.size && Number.isFinite(info.size.width) && Number.isFinite(info.size.height)) {
    const parsedFromSize: PixelMapSize = {
      width: info.size.width,
      height: info.size.height
    };
    return parsedFromSize;
  }
  if (Number.isFinite(info.width) && Number.isFinite(info.height)) {
    const parsedFromPlain: PixelMapSize = {
      width: info.width as number,
      height: info.height as number
    };
    return parsedFromPlain;
  }
  return undefined;
}
