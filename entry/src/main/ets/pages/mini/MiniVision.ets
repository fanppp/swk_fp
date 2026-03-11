import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import image from '@ohos.multimedia.image';

interface SnapshotWindowLike {
  snapshot?: () => Promise<Object>;
  snapshotSync?: () => Object;
}

export async function captureFullScreenshot(context: common.UIAbilityContext): Promise<image.PixelMap> {
  const hostWindow = await window.getLastWindow(context) as Object as SnapshotWindowLike;
  if (hostWindow.snapshot) {
    return await hostWindow.snapshot() as image.PixelMap;
  }
  if (hostWindow.snapshotSync) {
    return hostWindow.snapshotSync() as image.PixelMap;
  }
  throw new Error('snapshot unavailable');
}

export async function pixelMapToCompressedBase64(
  pixelMap: image.PixelMap,
  quality: number = 40
): Promise<string> {
  const packer = image.createImagePacker();
  try {
    const arrayBuffer = await packer.packToData(pixelMap, { format: 'image/jpeg', quality });
    const bytes = new Uint8Array(arrayBuffer);
    const base64Helper = new util.Base64Helper();
    return base64Helper.encodeToStringSync(bytes);
  } finally {
    await packer.release();
  }
}
