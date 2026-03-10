export type MiniTaskType =
  | 'concertTicket'
  | 'trainTicket'
  | 'redPacket'
  | 'taxi'
  | 'reminder'
  | 'generic';
export type MiniScheduleType = 'once' | 'weekly' | 'daily' | 'unknown';
export type MiniTaskExecutionStatus = 'idle' | 'waiting' | 'running' | 'success' | 'failed';

export interface MiniTaskSchedule {
  rawText: string;
  scheduleType: MiniScheduleType;
  timeText: string;
  weekdayText?: string;
}

export interface MiniTaskExecution {
  status: MiniTaskExecutionStatus;
  logText: string;
  nextTriggerAt?: number;
  lastRunAt?: number;
  resultText?: string;
}

// Keep field names aligned with the existing TaskCardData format.
export interface MiniTaskCardData {
  id: number;
  source: string;
  taskType: MiniTaskType;
  title: string;
  description: string;
  createdByInput: string;
  schedule: MiniTaskSchedule;
  createdAt: number;
  execution?: MiniTaskExecution;
}

export interface MiniTaskRequest {
  requestId: string;
  requestType: MiniTaskType;
  requestDescription: string;
  taskTime: string;
  requestPageUri: string;
  title: string;
  createdAt: number;
}
