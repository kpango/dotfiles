/**
 * 大きな JSON ペイロードを保存・転送できるサイズに丸める共通ポリシー。
 *
 * journal / mesh / observation など層ごとに「メッセージ全体の型」は意図的に異なる
 * (追記専用 JSONL、protobuf 風 payload、行プロトコル)。共通化できるのは型ではなく
 * 「上限バイト数を超えたら preview + truncated フラグへ置き換え、復元不能であることを
 * 呼び出し側へ明示する」という丸め方なので、そこだけをここに集約する。
 */

export interface BoundedJsonOptions {
  /** これ以下のバイト数ならそのまま返す。 */
  maxBytes: number;
  /** 上限超過時に残す先頭文字数。 */
  previewChars: number;
}

export interface BoundedJsonPayload {
  /** 元の値、または `{truncated, bytes, preview}`。 */
  value: unknown;
  truncated: boolean;
  /** JSON 表現のバイト数(直列化できない場合は 0)。 */
  bytes: number;
}

/** JSON 表現の UTF-8 バイト数。循環参照などで直列化できなければ undefined。 */
export function jsonByteLength(value: unknown): number | undefined {
  try {
    const text = JSON.stringify(value);
    return text === undefined ? 0 : Buffer.byteLength(text, "utf8");
  } catch {
    return undefined;
  }
}

/** 上限超過なら `{truncated:true, bytes, preview}` に置き換える。 */
export function boundJsonPayload(
  value: unknown,
  options: BoundedJsonOptions,
): BoundedJsonPayload {
  if (value === undefined) return { value, truncated: false, bytes: 0 };
  let text: string | undefined;
  try {
    text = JSON.stringify(value);
  } catch {
    // 直列化不能な値は呼び出し側の判断に委ねる(丸めない)
    return { value, truncated: false, bytes: 0 };
  }
  const bytes = text === undefined ? 0 : Buffer.byteLength(text, "utf8");
  if (bytes <= options.maxBytes) return { value, truncated: false, bytes };
  return {
    value: {
      truncated: true,
      bytes,
      preview: (text ?? "").slice(0, options.previewChars),
    },
    truncated: true,
    bytes,
  };
}
