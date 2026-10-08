import { apiClient } from './apiClient';
export interface LoadRequest { id: number; amount: number; currency: string; note?: string; status: string; updatedAt: string; adminEmailSent: boolean }
export interface AssignedCard {
  id: number; status: string; currency: string; availableBalance: number; pendingBalance: number;
  maskedCardNumber?: string; cardNumberLastFour?: string; cardholderName?: string; isPhysical: boolean;
  isLocked: boolean; pendingLoadRequest?: LoadRequest;
}
export interface UserCards { cards: AssignedCard[]; capabilities: { transactions: boolean; loadRequests: boolean } }
export interface CardHistory { data: {id:number; transactionType:string; amount:number; currency:string; status:string; merchantName?:string; description?:string; category?:string; transactionDate:string}[]; total:number; limit:number; offset:number }
const base = '/api/v1/mor/user/cards';
export async function userGet<T>(path = '', params?: object) { return (await apiClient.get<T>(`${base}${path}`, {params})).data; }
export async function userPost<T>(path: string, body: object = {}) { return (await apiClient.post<T>(`${base}${path}`, body)).data; }
