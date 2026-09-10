export type Message = {
  id: string;
  conversationId: string;
  senderId: string;
  text: string;
  createdAt: string;
  status: 'sending' | 'sent' | 'delivered' | 'read';
};

export type Conversation = {
  id: string;
  title: string;
  avatarUrl?: string;
  lastMessage?: string;
  updatedAt?: string;
  unreadCount: number;
};
