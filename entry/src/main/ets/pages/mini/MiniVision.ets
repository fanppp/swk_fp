import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import image from '@ohos.multimedia.image';
import { util } from '@kit.ArkTS';

const LOG_DOMAIN: number = 0x0523;
const LOG_TAG: string = 'MiniVision';

export interface MiniImageBase64Attachment {
  name: string;
  mimeType: 'image/png' | 'image/jpeg' | 'image/webp';
  base64: string;
}

export async function loadRawfileImageBase64(
  context: common.UIAbilityContext,
  rawFilePath: string
): Promise<MiniImageBase64Attachment> {
  const startTime = Date.now();
  const rawBytes = await context.resourceManager.getRawFileContent(rawFilePath);
  const imageSource = image.createImageSource(rawBytes.buffer);
  const packer = image.createImagePacker();
  try {
    const imageInfo = await imageSource.getImageInfo();
    const decodeStartTime = Date.now();
    const pixelMap = await imageSource.createPixelMap();
    const decodeDuration = Date.now() - decodeStartTime;
    try {
      const encodeStartTime = Date.now();
      const packed = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: 45
      });
      const encodeDuration = Date.now() - encodeStartTime;
      const base64StartTime = Date.now();
      const base64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(packed));
      const base64Duration = Date.now() - base64StartTime;
      const totalDuration = Date.now() - startTime;
      hilog.info(
        LOG_DOMAIN,
        LOG_TAG,
        'loadRawfileImageBase64 pixelMap file=%{public}s rawBytes=%{public}d src=%{public}dx%{public}d packedBytes=%{public}d base64Chars=%{public}d decodeMs=%{public}d encodeMs=%{public}d base64Ms=%{public}d totalMs=%{public}d',
        rawFilePath,
        rawBytes.length,
        imageInfo.size.width,
        imageInfo.size.height,
        packed.byteLength,
        base64.length,
        decodeDuration,
        encodeDuration,
        base64Duration,
        totalDuration
      );
      return {
        name: rawFilePath,
        mimeType: 'image/jpeg',
        base64
      };
    } finally {
      await pixelMap.release();
    }
  } finally {
    await packer.release();
    await imageSource.release();
  }
}
