# SnapLog – Entity Relationship Diagram

```mermaid
erDiagram
    USER ||--o{ ROOM_MEMBER : "joins via"
    ROOM ||--o{ ROOM_MEMBER : "has"
    USER ||--o{ MEDIA_LOG : uploads
    ROOM ||--o{ MEDIA_LOG : contains

    USER {
        uuid id PK
        string apple_user_id UK "unique, from Apple Sign-In"
        string email
        string display_name
        string avatar_url "nullable"
        timestamp created_at
    }

    ROOM {
        uuid id PK
        string name "nullable"
        string room_type "log | stack"
        int max_members "2, 3, 4, 5, or 20"
        string invite_code UK "unique, 6 chars"
        timestamp created_at
    }

    ROOM_MEMBER {
        uuid id PK
        uuid user_id FK "cascade delete"
        uuid room_id FK "cascade delete"
        string role "owner | member"
        timestamp joined_at
        timestamp created_at
    }

    MEDIA_LOG {
        uuid id PK
        uuid user_id FK "cascade delete"
        uuid room_id FK "cascade delete"
        string s3_key "raw/…, digests/…, or uploads/… in R2"
        double duration "0–60 seconds"
        timestamp created_at
    }
```

## Notes

- `ROOM_MEMBER` is the pivot table for the many-to-many `USER ↔ ROOM` relationship (Fluent `@Siblings` on both models).
- Unique indexes: `users.apple_user_id`, `rooms.invite_code`, and `(room_member.user_id, room_member.room_id)`.
- Deleting a `USER` or `ROOM` cascades to their `ROOM_MEMBER` rows and `MEDIA_LOG` rows.
- `MEDIA_LOG.s3_key` references objects in Cloudflare R2 (not a DB relation).
