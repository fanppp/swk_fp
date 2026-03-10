import { MiniTaskRequest } from './MiniTaskTypes';

export class MiniTaskRequestStore {
  private static instance: MiniTaskRequestStore;
  private latestRequest?: MiniTaskRequest;

  static getInstance(): MiniTaskRequestStore {
    if (!MiniTaskRequestStore.instance) {
      MiniTaskRequestStore.instance = new MiniTaskRequestStore();
    }
    return MiniTaskRequestStore.instance;
  }

  saveRequest(request: MiniTaskRequest): void {
    this.latestRequest = request;
  }

  getLatestRequest(): MiniTaskRequest | undefined {
    return this.latestRequest;
  }
}
