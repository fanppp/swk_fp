import { MiniScheduleType, MiniTaskCardData, MiniTaskType } from './MiniTaskTypes';

export interface MiniTaskBuildInput {
  taskType: MiniTaskType;
  title: string;
  timeText: string;
  scheduleType?: MiniScheduleType;
  extraInfo?: string;
}

export function buildTicketTask(input: string, timeText: string): MiniTaskCardData {
  const parsed: MiniTaskBuildInput = {
    taskType: 'concertTicket',
    title: '抢演出票',
    timeText: timeText,
    scheduleType: 'once'
  };
  return buildTaskFromParsedInfo(input, parsed);
}

export function buildTaskFromParsedInfo(input: string, parsed: MiniTaskBuildInput): MiniTaskCardData {
  const normalizedTime = normalizeTaskTimeText(parsed.timeText);
  const title = normalizeTitle(parsed.title, parsed.taskType);
  const scheduleType = parsed.scheduleType ?? 'once';
  const timestamp = Date.now();
  const descPrefix = getDescriptionPrefix(parsed.taskType);
  const descTime = normalizedTime.length > 0 ? normalizedTime : '时间待定';
  const extra = parsed.extraInfo && parsed.extraInfo.trim().length > 0 ? `，补充：${parsed.extraInfo.trim()}` : '';

  return {
    id: timestamp,
    source: '小艺任务',
    taskType: parsed.taskType,
    title,
    description: `在${descTime}，${descPrefix}${extra}。`,
    createdByInput: input,
    schedule: {
      rawText: input,
      scheduleType,
      timeText: descTime
    },
    createdAt: timestamp,
    execution: {
      status: 'idle',
      logText: '可手动模拟执行'
    }
  };
}

function normalizeTaskTimeText(timeText: string): string {
  const text = timeText.trim().replace(/：/g, ':').replace(/\s+/g, ' ');
  if (text.length === 0) {
    return '';
  }

  const fullDateMatch = text.match(/^(\d{4})[./-](\d{1,2})[./-](\d{1,2})\s+(\d{1,2}):(\d{1,2})/);
  if (fullDateMatch) {
    const year = Number(fullDateMatch[1]);
    const month = Number(fullDateMatch[2]);
    const day = Number(fullDateMatch[3]);
    const hour = Number(fullDateMatch[4]);
    const minute = Number(fullDateMatch[5]);
    if (isValidDateTime(year, month, day, hour, minute)) {
      return `${year}.${pad2(month)}.${pad2(day)} ${pad2(hour)}:${pad2(minute)}`;
    }
  }

  const hmMatch = text.match(/^(\d{1,2}):(\d{1,2})$/);
  if (hmMatch) {
    const hour = Number(hmMatch[1]);
    const minute = Number(hmMatch[2]);
    if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
      return `${pad2(hour)}:${pad2(minute)}`;
    }
  }

  return text;
}

function normalizeTitle(title: string, taskType: MiniTaskType): string {
  const text = title.trim();
  if (text.length > 0) {
    return text;
  }
  switch (taskType) {
    case 'concertTicket':
      return '抢演出票';
    case 'trainTicket':
      return '抢火车票';
    case 'redPacket':
      return '红包任务';
    case 'taxi':
      return '打车任务';
    case 'reminder':
      return '提醒任务';
    default:
      return '通用任务';
  }
}

function getDescriptionPrefix(taskType: MiniTaskType): string {
  switch (taskType) {
    case 'concertTicket':
      return '执行抢演出票任务';
    case 'trainTicket':
      return '执行火车票抢票任务';
    case 'redPacket':
      return '处理红包相关任务';
    case 'taxi':
      return '执行打车任务';
    case 'reminder':
      return '执行提醒任务';
    default:
      return '执行任务';
  }
}

function isValidDateTime(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number
): boolean {
  if (!Number.isFinite(year) || year < 1970 || year > 9999) {
    return false;
  }
  if (!Number.isFinite(month) || month < 1 || month > 12) {
    return false;
  }
  if (!Number.isFinite(day) || day < 1 || day > 31) {
    return false;
  }
  if (!Number.isFinite(hour) || hour < 0 || hour > 23) {
    return false;
  }
  if (!Number.isFinite(minute) || minute < 0 || minute > 59) {
    return false;
  }
  return true;
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}
