export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      audit_log: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          detail: Json
          id: number
          target_id: string | null
          target_table: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          detail?: Json
          id?: never
          target_id?: string | null
          target_table?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          detail?: Json
          id?: never
          target_id?: string | null
          target_table?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      blocks: {
        Row: {
          blocked_id: string
          blocker_id: string
          created_at: string
        }
        Insert: {
          blocked_id: string
          blocker_id: string
          created_at?: string
        }
        Update: {
          blocked_id?: string
          blocker_id?: string
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "blocks_blocked_id_fkey"
            columns: ["blocked_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "blocks_blocker_id_fkey"
            columns: ["blocker_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      call_participants: {
        Row: {
          call_id: string
          joined_at: string | null
          left_at: string | null
          muted: boolean
          user_id: string
          video_on: boolean
        }
        Insert: {
          call_id: string
          joined_at?: string | null
          left_at?: string | null
          muted?: boolean
          user_id: string
          video_on?: boolean
        }
        Update: {
          call_id?: string
          joined_at?: string | null
          left_at?: string | null
          muted?: boolean
          user_id?: string
          video_on?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "call_participants_call_id_fkey"
            columns: ["call_id"]
            isOneToOne: false
            referencedRelation: "calls"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "call_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      call_signals: {
        Row: {
          call_id: string
          created_at: string
          id: number
          payload: Json
          recipient_id: string | null
          sender_id: string
          type: string
        }
        Insert: {
          call_id: string
          created_at?: string
          id?: never
          payload: Json
          recipient_id?: string | null
          sender_id: string
          type: string
        }
        Update: {
          call_id?: string
          created_at?: string
          id?: never
          payload?: Json
          recipient_id?: string | null
          sender_id?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "call_signals_call_id_fkey"
            columns: ["call_id"]
            isOneToOne: false
            referencedRelation: "calls"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "call_signals_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "call_signals_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      calls: {
        Row: {
          conversation_id: string
          created_at: string
          created_by: string
          duration_seconds: number | null
          end_reason: string | null
          ended_at: string | null
          id: string
          kind: Database["public"]["Enums"]["call_kind"]
          started_at: string | null
          status: Database["public"]["Enums"]["call_status"]
        }
        Insert: {
          conversation_id: string
          created_at?: string
          created_by: string
          duration_seconds?: number | null
          end_reason?: string | null
          ended_at?: string | null
          id?: string
          kind: Database["public"]["Enums"]["call_kind"]
          started_at?: string | null
          status?: Database["public"]["Enums"]["call_status"]
        }
        Update: {
          conversation_id?: string
          created_at?: string
          created_by?: string
          duration_seconds?: number | null
          end_reason?: string | null
          ended_at?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["call_kind"]
          started_at?: string | null
          status?: Database["public"]["Enums"]["call_status"]
        }
        Relationships: [
          {
            foreignKeyName: "calls_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "calls_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      collection_templates: {
        Row: {
          accent_color: string | null
          created_at: string
          description: string | null
          icon: string
          id: string
          name: string
          slug: string
          sort_order: number
          suggested_fields: Json
          suggested_tags: string[]
        }
        Insert: {
          accent_color?: string | null
          created_at?: string
          description?: string | null
          icon: string
          id?: string
          name: string
          slug: string
          sort_order?: number
          suggested_fields?: Json
          suggested_tags?: string[]
        }
        Update: {
          accent_color?: string | null
          created_at?: string
          description?: string | null
          icon?: string
          id?: string
          name?: string
          slug?: string
          sort_order?: number
          suggested_fields?: Json
          suggested_tags?: string[]
        }
        Relationships: []
      }
      collections: {
        Row: {
          accent_color: string | null
          comment_count: number
          cover_blurhash: string | null
          cover_path: string | null
          created_at: string
          deleted_at: string | null
          description: string | null
          hidden_at: string | null
          id: string
          is_featured: boolean
          is_pinned: boolean
          item_count: number
          like_count: number
          name: string
          position: number
          repost_count: number
          save_count: number
          search_tsv: unknown
          slug: string
          subcollection_count: number
          template_id: string | null
          updated_at: string
          user_id: string
          view_count: number
          visibility: Database["public"]["Enums"]["visibility"]
        }
        Insert: {
          accent_color?: string | null
          comment_count?: number
          cover_blurhash?: string | null
          cover_path?: string | null
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          hidden_at?: string | null
          id?: string
          is_featured?: boolean
          is_pinned?: boolean
          item_count?: number
          like_count?: number
          name: string
          position?: number
          repost_count?: number
          save_count?: number
          search_tsv?: unknown
          slug: string
          subcollection_count?: number
          template_id?: string | null
          updated_at?: string
          user_id: string
          view_count?: number
          visibility?: Database["public"]["Enums"]["visibility"]
        }
        Update: {
          accent_color?: string | null
          comment_count?: number
          cover_blurhash?: string | null
          cover_path?: string | null
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          hidden_at?: string | null
          id?: string
          is_featured?: boolean
          is_pinned?: boolean
          item_count?: number
          like_count?: number
          name?: string
          position?: number
          repost_count?: number
          save_count?: number
          search_tsv?: unknown
          slug?: string
          subcollection_count?: number
          template_id?: string | null
          updated_at?: string
          user_id?: string
          view_count?: number
          visibility?: Database["public"]["Enums"]["visibility"]
        }
        Relationships: [
          {
            foreignKeyName: "collections_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "collection_templates"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "collections_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      comments: {
        Row: {
          author_id: string
          body: string
          created_at: string
          deleted_at: string | null
          depth: number
          edited_at: string | null
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          hidden_at: string | null
          id: string
          like_count: number
          parent_id: string | null
          reply_count: number
          updated_at: string
        }
        Insert: {
          author_id: string
          body: string
          created_at?: string
          deleted_at?: string | null
          depth?: number
          edited_at?: string | null
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          hidden_at?: string | null
          id?: string
          like_count?: number
          parent_id?: string | null
          reply_count?: number
          updated_at?: string
        }
        Update: {
          author_id?: string
          body?: string
          created_at?: string
          deleted_at?: string | null
          depth?: number
          edited_at?: string | null
          entity_id?: string
          entity_type?: Database["public"]["Enums"]["entity_type"]
          hidden_at?: string | null
          id?: string
          like_count?: number
          parent_id?: string | null
          reply_count?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comments_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
        ]
      }
      conversation_members: {
        Row: {
          archived_at: string | null
          cleared_at: string | null
          conversation_id: string
          joined_at: string
          last_read_at: string | null
          left_at: string | null
          muted_until: string | null
          pinned: boolean
          role: Database["public"]["Enums"]["member_role"]
          unread_count: number
          user_id: string
        }
        Insert: {
          archived_at?: string | null
          cleared_at?: string | null
          conversation_id: string
          joined_at?: string
          last_read_at?: string | null
          left_at?: string | null
          muted_until?: string | null
          pinned?: boolean
          role?: Database["public"]["Enums"]["member_role"]
          unread_count?: number
          user_id: string
        }
        Update: {
          archived_at?: string | null
          cleared_at?: string | null
          conversation_id?: string
          joined_at?: string
          last_read_at?: string | null
          left_at?: string | null
          muted_until?: string | null
          pinned?: boolean
          role?: Database["public"]["Enums"]["member_role"]
          unread_count?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversation_members_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversation_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      conversations: {
        Row: {
          avatar_path: string | null
          created_at: string
          created_by: string
          description: string | null
          dm_key: string | null
          id: string
          kind: Database["public"]["Enums"]["conversation_kind"]
          last_message_at: string | null
          last_message_by: string | null
          last_message_preview: string | null
          title: string | null
          updated_at: string
        }
        Insert: {
          avatar_path?: string | null
          created_at?: string
          created_by: string
          description?: string | null
          dm_key?: string | null
          id?: string
          kind: Database["public"]["Enums"]["conversation_kind"]
          last_message_at?: string | null
          last_message_by?: string | null
          last_message_preview?: string | null
          title?: string | null
          updated_at?: string
        }
        Update: {
          avatar_path?: string | null
          created_at?: string
          created_by?: string
          description?: string | null
          dm_key?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["conversation_kind"]
          last_message_at?: string | null
          last_message_by?: string | null
          last_message_preview?: string | null
          title?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conversations_last_message_by_fkey"
            columns: ["last_message_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      entity_tags: {
        Row: {
          created_at: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          tag_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          tag_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          entity_id?: string
          entity_type?: Database["public"]["Enums"]["entity_type"]
          tag_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "entity_tags_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "entity_tags_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      entity_views: {
        Row: {
          created_at: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          viewed_on: string
          viewer_id: string
        }
        Insert: {
          created_at?: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          viewed_on?: string
          viewer_id: string
        }
        Update: {
          created_at?: string
          entity_id?: string
          entity_type?: Database["public"]["Enums"]["entity_type"]
          viewed_on?: string
          viewer_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "entity_views_viewer_id_fkey"
            columns: ["viewer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      follows: {
        Row: {
          created_at: string
          follower_id: string
          following_id: string
        }
        Insert: {
          created_at?: string
          follower_id: string
          following_id: string
        }
        Update: {
          created_at?: string
          follower_id?: string
          following_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "follows_follower_id_fkey"
            columns: ["follower_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "follows_following_id_fkey"
            columns: ["following_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      item_media: {
        Row: {
          alt_text: string | null
          blurhash: string | null
          bytes: number | null
          created_at: string
          dominant_color: string | null
          height: number | null
          id: string
          item_id: string
          mime_type: string | null
          position: number
          storage_path: string
          user_id: string
          width: number | null
        }
        Insert: {
          alt_text?: string | null
          blurhash?: string | null
          bytes?: number | null
          created_at?: string
          dominant_color?: string | null
          height?: number | null
          id?: string
          item_id: string
          mime_type?: string | null
          position?: number
          storage_path: string
          user_id: string
          width?: number | null
        }
        Update: {
          alt_text?: string | null
          blurhash?: string | null
          bytes?: number | null
          created_at?: string
          dominant_color?: string | null
          height?: number | null
          id?: string
          item_id?: string
          mime_type?: string | null
          position?: number
          storage_path?: string
          user_id?: string
          width?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "item_media_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "item_media_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      items: {
        Row: {
          acquisition_date: string | null
          acquisition_place: string | null
          attributes: Json
          brand: string | null
          collection_id: string
          comment_count: number
          condition: string | null
          cover_blurhash: string | null
          cover_height: number | null
          cover_path: string | null
          cover_width: number | null
          created_at: string
          currency: string | null
          deleted_at: string | null
          description: string | null
          hidden_at: string | null
          id: string
          is_favorite: boolean
          like_count: number
          media_count: number
          model: string | null
          position: number
          purchase_price: number | null
          rarity: string | null
          repost_count: number
          save_count: number
          search_tsv: unknown
          subcollection_id: string | null
          title: string
          updated_at: string
          user_id: string
          view_count: number
          visibility: Database["public"]["Enums"]["visibility"] | null
          year: number | null
        }
        Insert: {
          acquisition_date?: string | null
          acquisition_place?: string | null
          attributes?: Json
          brand?: string | null
          collection_id: string
          comment_count?: number
          condition?: string | null
          cover_blurhash?: string | null
          cover_height?: number | null
          cover_path?: string | null
          cover_width?: number | null
          created_at?: string
          currency?: string | null
          deleted_at?: string | null
          description?: string | null
          hidden_at?: string | null
          id?: string
          is_favorite?: boolean
          like_count?: number
          media_count?: number
          model?: string | null
          position?: number
          purchase_price?: number | null
          rarity?: string | null
          repost_count?: number
          save_count?: number
          search_tsv?: unknown
          subcollection_id?: string | null
          title: string
          updated_at?: string
          user_id: string
          view_count?: number
          visibility?: Database["public"]["Enums"]["visibility"] | null
          year?: number | null
        }
        Update: {
          acquisition_date?: string | null
          acquisition_place?: string | null
          attributes?: Json
          brand?: string | null
          collection_id?: string
          comment_count?: number
          condition?: string | null
          cover_blurhash?: string | null
          cover_height?: number | null
          cover_path?: string | null
          cover_width?: number | null
          created_at?: string
          currency?: string | null
          deleted_at?: string | null
          description?: string | null
          hidden_at?: string | null
          id?: string
          is_favorite?: boolean
          like_count?: number
          media_count?: number
          model?: string | null
          position?: number
          purchase_price?: number | null
          rarity?: string | null
          repost_count?: number
          save_count?: number
          search_tsv?: unknown
          subcollection_id?: string | null
          title?: string
          updated_at?: string
          user_id?: string
          view_count?: number
          visibility?: Database["public"]["Enums"]["visibility"] | null
          year?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "items_collection_id_fkey"
            columns: ["collection_id"]
            isOneToOne: false
            referencedRelation: "collections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_subcollection_id_fkey"
            columns: ["subcollection_id"]
            isOneToOne: false
            referencedRelation: "subcollections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "items_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      likes: {
        Row: {
          created_at: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          user_id: string
        }
        Insert: {
          created_at?: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          user_id: string
        }
        Update: {
          created_at?: string
          entity_id?: string
          entity_type?: Database["public"]["Enums"]["entity_type"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "likes_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      message_reactions: {
        Row: {
          created_at: string
          emoji: string
          message_id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          emoji: string
          message_id: string
          user_id: string
        }
        Update: {
          created_at?: string
          emoji?: string
          message_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_reactions_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_reactions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      message_receipts: {
        Row: {
          message_id: string
          read_at: string
          user_id: string
        }
        Insert: {
          message_id: string
          read_at?: string
          user_id: string
        }
        Update: {
          message_id?: string
          read_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_receipts_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_receipts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          attachments: Json
          author_id: string
          body: string | null
          call_id: string | null
          conversation_id: string
          created_at: string
          deleted_at: string | null
          edited_at: string | null
          id: string
          kind: Database["public"]["Enums"]["message_kind"]
          reply_to_id: string | null
          shared_entity_id: string | null
          shared_entity_type: Database["public"]["Enums"]["entity_type"] | null
          updated_at: string
        }
        Insert: {
          attachments?: Json
          author_id: string
          body?: string | null
          call_id?: string | null
          conversation_id: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["message_kind"]
          reply_to_id?: string | null
          shared_entity_id?: string | null
          shared_entity_type?: Database["public"]["Enums"]["entity_type"] | null
          updated_at?: string
        }
        Update: {
          attachments?: Json
          author_id?: string
          body?: string | null
          call_id?: string | null
          conversation_id?: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["message_kind"]
          reply_to_id?: string | null
          shared_entity_id?: string | null
          shared_entity_type?: Database["public"]["Enums"]["entity_type"] | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_call_fk"
            columns: ["call_id"]
            isOneToOne: false
            referencedRelation: "calls"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_reply_to_id_fkey"
            columns: ["reply_to_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
        ]
      }
      moderation_actions: {
        Row: {
          action: Database["public"]["Enums"]["mod_action"]
          created_at: string
          entity_id: string | null
          entity_type: Database["public"]["Enums"]["entity_type"] | null
          expires_at: string | null
          id: string
          moderator_id: string
          reason: string | null
          report_id: string | null
          target_user_id: string | null
        }
        Insert: {
          action: Database["public"]["Enums"]["mod_action"]
          created_at?: string
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"] | null
          expires_at?: string | null
          id?: string
          moderator_id: string
          reason?: string | null
          report_id?: string | null
          target_user_id?: string | null
        }
        Update: {
          action?: Database["public"]["Enums"]["mod_action"]
          created_at?: string
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"] | null
          expires_at?: string | null
          id?: string
          moderator_id?: string
          reason?: string | null
          report_id?: string | null
          target_user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "moderation_actions_moderator_id_fkey"
            columns: ["moderator_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_actions_report_id_fkey"
            columns: ["report_id"]
            isOneToOne: false
            referencedRelation: "reports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "moderation_actions_target_user_id_fkey"
            columns: ["target_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      mutes: {
        Row: {
          created_at: string
          muted_id: string
          muter_id: string
        }
        Insert: {
          created_at?: string
          muted_id: string
          muter_id: string
        }
        Update: {
          created_at?: string
          muted_id?: string
          muter_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "mutes_muted_id_fkey"
            columns: ["muted_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "mutes_muter_id_fkey"
            columns: ["muter_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          actor_id: string | null
          body: string | null
          call_id: string | null
          comment_id: string | null
          conversation_id: string | null
          created_at: string
          entity_id: string | null
          entity_type: Database["public"]["Enums"]["entity_type"] | null
          id: string
          message_id: string | null
          read_at: string | null
          type: Database["public"]["Enums"]["notification_type"]
          user_id: string
        }
        Insert: {
          actor_id?: string | null
          body?: string | null
          call_id?: string | null
          comment_id?: string | null
          conversation_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"] | null
          id?: string
          message_id?: string | null
          read_at?: string | null
          type: Database["public"]["Enums"]["notification_type"]
          user_id: string
        }
        Update: {
          actor_id?: string | null
          body?: string | null
          call_id?: string | null
          comment_id?: string | null
          conversation_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"] | null
          id?: string
          message_id?: string | null
          read_at?: string | null
          type?: Database["public"]["Enums"]["notification_type"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_call_id_fkey"
            columns: ["call_id"]
            isOneToOne: false
            referencedRelation: "calls"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_comment_id_fkey"
            columns: ["comment_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      posts: {
        Row: {
          author_id: string
          body: string | null
          comment_count: number
          created_at: string
          deleted_at: string | null
          edited_at: string | null
          entity_id: string | null
          entity_type: Database["public"]["Enums"]["entity_type"] | null
          hidden_at: string | null
          id: string
          kind: Database["public"]["Enums"]["post_kind"]
          like_count: number
          reply_count: number
          reply_to_post_id: string | null
          repost_count: number
          root_post_id: string | null
          save_count: number
          search_tsv: unknown
          updated_at: string
          view_count: number
          visibility: Database["public"]["Enums"]["visibility"]
        }
        Insert: {
          author_id: string
          body?: string | null
          comment_count?: number
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"] | null
          hidden_at?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["post_kind"]
          like_count?: number
          reply_count?: number
          reply_to_post_id?: string | null
          repost_count?: number
          root_post_id?: string | null
          save_count?: number
          search_tsv?: unknown
          updated_at?: string
          view_count?: number
          visibility?: Database["public"]["Enums"]["visibility"]
        }
        Update: {
          author_id?: string
          body?: string | null
          comment_count?: number
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"] | null
          hidden_at?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["post_kind"]
          like_count?: number
          reply_count?: number
          reply_to_post_id?: string | null
          repost_count?: number
          root_post_id?: string | null
          save_count?: number
          search_tsv?: unknown
          updated_at?: string
          view_count?: number
          visibility?: Database["public"]["Enums"]["visibility"]
        }
        Relationships: [
          {
            foreignKeyName: "posts_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "posts_reply_to_post_id_fkey"
            columns: ["reply_to_post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "posts_root_post_id_fkey"
            columns: ["root_post_id"]
            isOneToOne: false
            referencedRelation: "posts"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          accent_color: string | null
          account_visibility: Database["public"]["Enums"]["visibility"]
          allow_messages_from: string
          avatar_path: string | null
          banner_path: string | null
          bio: string | null
          collection_count: number
          created_at: string
          display_name: string
          follower_count: number
          following_count: number
          id: string
          is_suspended: boolean
          is_verified: boolean
          item_count: number
          last_seen_at: string | null
          location: string | null
          onboarded_at: string | null
          search_tsv: unknown
          show_similarity: boolean
          suspended_until: string | null
          suspension_reason: string | null
          updated_at: string
          username: string
          website: string | null
        }
        Insert: {
          accent_color?: string | null
          account_visibility?: Database["public"]["Enums"]["visibility"]
          allow_messages_from?: string
          avatar_path?: string | null
          banner_path?: string | null
          bio?: string | null
          collection_count?: number
          created_at?: string
          display_name: string
          follower_count?: number
          following_count?: number
          id: string
          is_suspended?: boolean
          is_verified?: boolean
          item_count?: number
          last_seen_at?: string | null
          location?: string | null
          onboarded_at?: string | null
          search_tsv?: unknown
          show_similarity?: boolean
          suspended_until?: string | null
          suspension_reason?: string | null
          updated_at?: string
          username: string
          website?: string | null
        }
        Update: {
          accent_color?: string | null
          account_visibility?: Database["public"]["Enums"]["visibility"]
          allow_messages_from?: string
          avatar_path?: string | null
          banner_path?: string | null
          bio?: string | null
          collection_count?: number
          created_at?: string
          display_name?: string
          follower_count?: number
          following_count?: number
          id?: string
          is_suspended?: boolean
          is_verified?: boolean
          item_count?: number
          last_seen_at?: string | null
          location?: string | null
          onboarded_at?: string | null
          search_tsv?: unknown
          show_similarity?: boolean
          suspended_until?: string | null
          suspension_reason?: string | null
          updated_at?: string
          username?: string
          website?: string | null
        }
        Relationships: []
      }
      push_tokens: {
        Row: {
          created_at: string
          id: string
          platform: string
          token: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          platform: string
          token: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          platform?: string
          token?: string
          user_id?: string
        }
        Relationships: []
      }
      reports: {
        Row: {
          assigned_to: string | null
          created_at: string
          details: string | null
          entity_id: string | null
          entity_type: Database["public"]["Enums"]["entity_type"] | null
          id: string
          message_id: string | null
          priority: number
          reason: Database["public"]["Enums"]["report_reason"]
          reported_user_id: string | null
          reporter_id: string
          resolution: string | null
          resolved_at: string | null
          resolved_by: string | null
          status: Database["public"]["Enums"]["report_status"]
        }
        Insert: {
          assigned_to?: string | null
          created_at?: string
          details?: string | null
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"] | null
          id?: string
          message_id?: string | null
          priority?: number
          reason: Database["public"]["Enums"]["report_reason"]
          reported_user_id?: string | null
          reporter_id: string
          resolution?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: Database["public"]["Enums"]["report_status"]
        }
        Update: {
          assigned_to?: string | null
          created_at?: string
          details?: string | null
          entity_id?: string | null
          entity_type?: Database["public"]["Enums"]["entity_type"] | null
          id?: string
          message_id?: string | null
          priority?: number
          reason?: Database["public"]["Enums"]["report_reason"]
          reported_user_id?: string | null
          reporter_id?: string
          resolution?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: Database["public"]["Enums"]["report_status"]
        }
        Relationships: [
          {
            foreignKeyName: "reports_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_message_id_fkey"
            columns: ["message_id"]
            isOneToOne: false
            referencedRelation: "messages"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reported_user_id_fkey"
            columns: ["reported_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_reporter_id_fkey"
            columns: ["reporter_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reports_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      reposts: {
        Row: {
          created_at: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          quote_text: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          quote_text?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          entity_id?: string
          entity_type?: Database["public"]["Enums"]["entity_type"]
          quote_text?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reposts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      saves: {
        Row: {
          created_at: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          note: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          note?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          entity_id?: string
          entity_type?: Database["public"]["Enums"]["entity_type"]
          note?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "saves_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      share_events: {
        Row: {
          channel: string
          created_at: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          id: number
          user_id: string | null
        }
        Insert: {
          channel: string
          created_at?: string
          entity_id: string
          entity_type: Database["public"]["Enums"]["entity_type"]
          id?: never
          user_id?: string | null
        }
        Update: {
          channel?: string
          created_at?: string
          entity_id?: string
          entity_type?: Database["public"]["Enums"]["entity_type"]
          id?: never
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "share_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      subcollections: {
        Row: {
          collection_id: string
          comment_count: number
          cover_blurhash: string | null
          cover_path: string | null
          created_at: string
          deleted_at: string | null
          description: string | null
          hidden_at: string | null
          id: string
          item_count: number
          like_count: number
          name: string
          position: number
          repost_count: number
          save_count: number
          search_tsv: unknown
          slug: string
          updated_at: string
          user_id: string
          view_count: number
          visibility: Database["public"]["Enums"]["visibility"] | null
        }
        Insert: {
          collection_id: string
          comment_count?: number
          cover_blurhash?: string | null
          cover_path?: string | null
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          hidden_at?: string | null
          id?: string
          item_count?: number
          like_count?: number
          name: string
          position?: number
          repost_count?: number
          save_count?: number
          search_tsv?: unknown
          slug: string
          updated_at?: string
          user_id: string
          view_count?: number
          visibility?: Database["public"]["Enums"]["visibility"] | null
        }
        Update: {
          collection_id?: string
          comment_count?: number
          cover_blurhash?: string | null
          cover_path?: string | null
          created_at?: string
          deleted_at?: string | null
          description?: string | null
          hidden_at?: string | null
          id?: string
          item_count?: number
          like_count?: number
          name?: string
          position?: number
          repost_count?: number
          save_count?: number
          search_tsv?: unknown
          slug?: string
          updated_at?: string
          user_id?: string
          view_count?: number
          visibility?: Database["public"]["Enums"]["visibility"] | null
        }
        Relationships: [
          {
            foreignKeyName: "subcollections_collection_id_fkey"
            columns: ["collection_id"]
            isOneToOne: false
            referencedRelation: "collections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subcollections_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      tags: {
        Row: {
          created_at: string
          id: string
          name: string
          slug: string
          use_count: number
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          slug: string
          use_count?: number
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          slug?: string
          use_count?: number
        }
        Relationships: []
      }
      user_matches: {
        Row: {
          computed_at: string
          other_id: string
          score: number
          shared_tags: string[]
          user_id: string
        }
        Insert: {
          computed_at?: string
          other_id: string
          score: number
          shared_tags?: string[]
          user_id: string
        }
        Update: {
          computed_at?: string
          other_id?: string
          score?: number
          shared_tags?: string[]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_matches_other_id_fkey"
            columns: ["other_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_matches_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          created_at: string
          granted_by: string | null
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          granted_by?: string | null
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          granted_by?: string | null
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      user_taste: {
        Row: {
          tag_id: string
          updated_at: string
          user_id: string
          weight: number
        }
        Insert: {
          tag_id: string
          updated_at?: string
          user_id: string
          weight?: number
        }
        Update: {
          tag_id?: string
          updated_at?: string
          user_id?: string
          weight?: number
        }
        Relationships: [
          {
            foreignKeyName: "user_taste_tag_id_fkey"
            columns: ["tag_id"]
            isOneToOne: false
            referencedRelation: "tags"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_taste_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      add_comment: {
        Args: {
          p_body: string
          p_id: string
          p_parent?: string
          p_type: Database["public"]["Enums"]["entity_type"]
        }
        Returns: Json
      }
      add_group_members: {
        Args: { p_conversation: string; p_members: string[] }
        Returns: number
      }
      admin_list_reports: {
        Args: {
          p_limit?: number
          p_offset?: number
          p_status?: Database["public"]["Enums"]["report_status"]
        }
        Returns: Json
      }
      admin_metrics: { Args: never; Returns: Json }
      admin_moderate_entity: {
        Args: {
          p_hidden: boolean
          p_id: string
          p_reason?: string
          p_type: Database["public"]["Enums"]["entity_type"]
        }
        Returns: Json
      }
      admin_resolve_report: {
        Args: {
          p_action: Database["public"]["Enums"]["mod_action"]
          p_reason?: string
          p_report: string
          p_suspend_days?: number
        }
        Returns: Json
      }
      admin_set_role: {
        Args: {
          p_grant?: boolean
          p_role: Database["public"]["Enums"]["app_role"]
          p_user: string
        }
        Returns: Json
      }
      admin_set_user_state: {
        Args: {
          p_days?: number
          p_reason?: string
          p_suspended: boolean
          p_user: string
        }
        Returns: Json
      }
      admin_set_verified: {
        Args: { p_user: string; p_verified: boolean }
        Returns: Json
      }
      admin_user_detail: { Args: { p_user: string }; Returns: Json }
      audit: {
        Args: {
          p_action: string
          p_detail?: Json
          p_id: string
          p_table: string
        }
        Returns: undefined
      }
      blocked_with: { Args: { p_other: string }; Returns: boolean }
      can_see_owner: { Args: { p_owner: string }; Returns: boolean }
      can_view_entity: {
        Args: {
          p_id: string
          p_type: Database["public"]["Enums"]["entity_type"]
        }
        Returns: boolean
      }
      create_group: {
        Args: {
          p_avatar_path?: string
          p_description?: string
          p_members: string[]
          p_title: string
        }
        Returns: string
      }
      delete_comment: { Args: { p_comment: string }; Returns: Json }
      entity_counter: {
        Args: {
          p_col: string
          p_id: string
          p_type: Database["public"]["Enums"]["entity_type"]
        }
        Returns: number
      }
      entity_owner: {
        Args: {
          p_id: string
          p_type: Database["public"]["Enums"]["entity_type"]
        }
        Returns: string
      }
      get_closeup: {
        Args: {
          p_id: string
          p_type: Database["public"]["Enums"]["entity_type"]
        }
        Returns: Json
      }
      get_matches: {
        Args: { p_force?: boolean; p_limit?: number }
        Returns: Json
      }
      has_role: {
        Args: { p_role: Database["public"]["Enums"]["app_role"] }
        Returns: boolean
      }
      is_admin: { Args: never; Returns: boolean }
      is_conversation_admin: {
        Args: { p_conversation: string }
        Returns: boolean
      }
      is_conversation_member: {
        Args: { p_conversation: string }
        Returns: boolean
      }
      is_staff: { Args: never; Returns: boolean }
      mark_conversation_read: {
        Args: { p_conversation: string }
        Returns: undefined
      }
      mark_notifications_read: { Args: { p_ids?: string[] }; Returns: number }
      nightly_maintenance: { Args: never; Returns: undefined }
      notify: {
        Args: {
          p_actor: string
          p_body?: string
          p_call?: string
          p_comment?: string
          p_conversation?: string
          p_entity_id?: string
          p_entity_type?: Database["public"]["Enums"]["entity_type"]
          p_message?: string
          p_type: Database["public"]["Enums"]["notification_type"]
          p_user: string
        }
        Returns: undefined
      }
      pulse_feed: {
        Args: { p_before?: string; p_limit?: number }
        Returns: Json
      }
      record_view: {
        Args: {
          p_id: string
          p_type: Database["public"]["Enums"]["entity_type"]
        }
        Returns: number
      }
      refresh_matches: {
        Args: { p_limit?: number; p_user: string }
        Returns: undefined
      }
      refresh_user_taste: { Args: { p_user: string }; Returns: undefined }
      remove_group_member: {
        Args: { p_conversation: string; p_member: string }
        Returns: undefined
      }
      require_auth: { Args: never; Returns: string }
      search_all: { Args: { p_limit?: number; p_q: string }; Returns: Json }
      set_group_member_role: {
        Args: {
          p_conversation: string
          p_member: string
          p_role: Database["public"]["Enums"]["member_role"]
        }
        Returns: undefined
      }
      start_dm: { Args: { p_other: string }; Returns: string }
      submit_report: {
        Args: {
          p_details?: string
          p_id?: string
          p_message?: string
          p_reason: Database["public"]["Enums"]["report_reason"]
          p_type?: Database["public"]["Enums"]["entity_type"]
          p_user?: string
        }
        Returns: Json
      }
      surf_feed: {
        Args: {
          p_filter?: string
          p_limit?: number
          p_offset?: number
          p_seed?: string
        }
        Returns: Database["public"]["CompositeTypes"]["surf_card"][]
        SetofOptions: {
          from: "*"
          to: "surf_card"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      toggle_follow: { Args: { p_user: string }; Returns: Json }
      toggle_like: {
        Args: {
          p_id: string
          p_type: Database["public"]["Enums"]["entity_type"]
        }
        Returns: Json
      }
      toggle_repost: {
        Args: {
          p_id: string
          p_quote?: string
          p_type: Database["public"]["Enums"]["entity_type"]
        }
        Returns: Json
      }
      toggle_save: {
        Args: {
          p_id: string
          p_note?: string
          p_type: Database["public"]["Enums"]["entity_type"]
        }
        Returns: Json
      }
      update_group_info: {
        Args: {
          p_avatar_path?: string
          p_conversation: string
          p_description?: string
          p_title?: string
        }
        Returns: undefined
      }
      visible_to_me: {
        Args: {
          p_owner: string
          p_vis: Database["public"]["Enums"]["visibility"]
        }
        Returns: boolean
      }
    }
    Enums: {
      app_role: "user" | "moderator" | "admin" | "superadmin"
      call_kind: "audio" | "video"
      call_status:
        | "ringing"
        | "active"
        | "ended"
        | "missed"
        | "declined"
        | "failed"
      conversation_kind: "dm" | "group"
      entity_type: "collection" | "subcollection" | "item" | "post" | "comment"
      member_role: "owner" | "admin" | "member"
      message_kind: "text" | "image" | "entity_share" | "system" | "call_event"
      mod_action:
        | "none"
        | "warn"
        | "hide_content"
        | "delete_content"
        | "suspend_user"
        | "ban_user"
        | "restore_content"
      notification_type:
        | "like"
        | "save"
        | "repost"
        | "comment"
        | "reply"
        | "mention"
        | "follow"
        | "message"
        | "call"
        | "match"
        | "system"
        | "moderation"
      post_kind: "post" | "quote" | "reply"
      report_reason:
        | "spam"
        | "nudity"
        | "harassment"
        | "hate"
        | "violence"
        | "self_harm"
        | "ip_violation"
        | "misinformation"
        | "impersonation"
        | "other"
      report_status: "open" | "reviewing" | "actioned" | "dismissed"
      visibility: "public" | "followers" | "private"
    }
    CompositeTypes: {
      surf_card: {
        entity_type: Database["public"]["Enums"]["entity_type"] | null
        entity_id: string | null
        owner_id: string | null
        username: string | null
        display_name: string | null
        avatar_path: string | null
        is_verified: boolean | null
        title: string | null
        subtitle: string | null
        cover_path: string | null
        cover_blurhash: string | null
        width: number | null
        height: number | null
        accent_color: string | null
        like_count: number | null
        save_count: number | null
        repost_count: number | null
        comment_count: number | null
        view_count: number | null
        child_count: number | null
        created_at: string | null
        score: number | null
        viewer_liked: boolean | null
        viewer_saved: boolean | null
        viewer_reposted: boolean | null
        viewer_follows: boolean | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["user", "moderator", "admin", "superadmin"],
      call_kind: ["audio", "video"],
      call_status: [
        "ringing",
        "active",
        "ended",
        "missed",
        "declined",
        "failed",
      ],
      conversation_kind: ["dm", "group"],
      entity_type: ["collection", "subcollection", "item", "post", "comment"],
      member_role: ["owner", "admin", "member"],
      message_kind: ["text", "image", "entity_share", "system", "call_event"],
      mod_action: [
        "none",
        "warn",
        "hide_content",
        "delete_content",
        "suspend_user",
        "ban_user",
        "restore_content",
      ],
      notification_type: [
        "like",
        "save",
        "repost",
        "comment",
        "reply",
        "mention",
        "follow",
        "message",
        "call",
        "match",
        "system",
        "moderation",
      ],
      post_kind: ["post", "quote", "reply"],
      report_reason: [
        "spam",
        "nudity",
        "harassment",
        "hate",
        "violence",
        "self_harm",
        "ip_violation",
        "misinformation",
        "impersonation",
        "other",
      ],
      report_status: ["open", "reviewing", "actioned", "dismissed"],
      visibility: ["public", "followers", "private"],
    },
  },
} as const
