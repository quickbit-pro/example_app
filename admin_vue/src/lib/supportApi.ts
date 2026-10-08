import { apiClient } from './apiClient';

export type TicketStatus = 'awaiting_support' | 'awaiting_user' | 'resolved';
export interface SupportTicket {
  id: string;
  subject: string;
  status: TicketStatus;
  createdAt: string;
  updatedAt: string;
  revision: string;
  customerId: string | null;
  customerName: string | null;
  customerEmail: string | null;
}
export interface TicketDetail {
  ticket: SupportTicket;
  messages: { id: string; isAdmin: boolean; body: string; createdAt: string }[];
}
export interface TicketPage { items: SupportTicket[]; totalCount: number }
const path = '/api/v1/admin/support-tickets';
export const supportApi = {
  async list(status: string, offset: number): Promise<TicketPage> {
    return (await apiClient.get<TicketPage>(path, { params: { status: status || undefined, offset, limit: 30 } })).data;
  },
  async get(id: string): Promise<TicketDetail> {
    return (await apiClient.get<TicketDetail>(`${path}/${encodeURIComponent(id)}`)).data;
  },
  async reply(id: string, body: string, revision: string): Promise<TicketDetail> {
    return (await apiClient.post<TicketDetail>(`${path}/${encodeURIComponent(id)}/replies`, { body, revision })).data;
  },
  async setStatus(id: string, status: string, revision: string): Promise<TicketDetail> {
    return (await apiClient.patch<TicketDetail>(`${path}/${encodeURIComponent(id)}/status`, { status, revision })).data;
  },
};
export const ticketStatusLabels: Record<TicketStatus, string> = {
  awaiting_support: 'Awaiting support', awaiting_user: 'Awaiting customer reply', resolved: 'Resolved',
};
