#pragma once
#include <stddef.h>
#include <stdint.h>

#define DECK_CLAUDE_MAX_SESSIONS 24
#define DECK_CLAUDE_BODY_MAX     8192
#define DECK_CLAUDE_ID_MAX       40
#define DECK_CLAUDE_REQ_MAX      16
#define DECK_CLAUDE_PROJECT_MAX  24
#define DECK_CLAUDE_TOOL_MAX     16
#define DECK_CLAUDE_MODEL_MAX    16
#define DECK_CLAUDE_SUMMARY_MAX  84
#define DECK_CLAUDE_REASON_MAX   16
#define DECK_AGENTS_RAIL_W       12  // px column for the total pill and scroll thumb
#define DECK_AGENT_DEFAULT_MS    100 // stands in for a zero frame duration

enum DeckClaudeState : uint8_t { DCS_WORKING = 0, DCS_PERMISSION, DCS_WAITING, DCS_DONE, DCS_COUNT };
enum DeckClaudeAction : uint8_t { DCA_APPROVE = 0, DCA_ALWAYS, DCA_DENY, DCA_INTERRUPT, DCA_FOCUS, DCA_COUNT };

struct DeckClaudeSession {
  char id[DECK_CLAUDE_ID_MAX];
  char project[DECK_CLAUDE_PROJECT_MAX];
  char model[DECK_CLAUDE_MODEL_MAX];
  uint8_t state;
  int8_t ctx;          // -1 unknown
  int32_t cost_cents;  // -1 unknown
  bool tmux;
  char name[DECK_CLAUDE_PROJECT_MAX];
  char tool[DECK_CLAUDE_TOOL_MAX];
  uint8_t agents;
  uint32_t since;      // 0 unknown
  uint8_t hat, tint;
  bool live;
};
struct DeckClaudeWindow { bool known; uint8_t pct; uint32_t resets_at; };
struct DeckClaudePrompt {
  bool present, tmux;
  uint8_t pending;
  char session[DECK_CLAUDE_ID_MAX];
  char request[DECK_CLAUDE_REQ_MAX];
  char project[DECK_CLAUDE_PROJECT_MAX];
  char tool[DECK_CLAUDE_TOOL_MAX];
  char summary[DECK_CLAUDE_SUMMARY_MAX];
};
struct DeckClaude {
  uint8_t count;
  uint8_t agents_total;
  DeckClaudeSession s[DECK_CLAUDE_MAX_SESSIONS];
  DeckClaudeWindow five_hour, seven_day;
  DeckClaudePrompt prompt;
};
struct DeckClaudeAck { bool ok; char request[DECK_CLAUDE_REQ_MAX]; char reason[DECK_CLAUDE_REASON_MAX]; };

bool        deck_claude_parse(const char *json, size_t len, DeckClaude *out);         // out untouched on false
bool        deck_claude_ack_parse(const char *json, size_t len, DeckClaudeAck *out);  // out untouched on false
bool        deck_claude_action_body(const char *session, const char *request, uint8_t action, char *out, size_t out_len);
int         deck_claude_state_from_name(const char *name);  // -1 if unknown
const char *deck_claude_action_name(uint8_t action);        // "" if out of range
void        deck_claude_copy(char *dst, size_t dst_len, const char *src);
void        deck_claude_format_reset(uint32_t resets_at, uint32_t now, char *out, size_t len);
size_t      deck_claude_age(char *out, size_t n, uint32_t since, uint32_t now);  // "" and 0 when unknown
void        deck_claude_format_cost(int32_t cents, char *out, size_t len);
bool        deck_claude_prompt_same(const DeckClaudePrompt *a, const DeckClaudePrompt *b);

struct DeckAgentSprites;
int  deck_claude_agents_grid(uint8_t w, uint8_t h, int box_w, int box_h, int *cols, int *rows, int *tw, int *th);
void deck_claude_agent_status(const DeckClaudeSession *s, uint32_t now, const char *sep, char *out, size_t n);
int  deck_claude_agent_tag(const DeckAgentSprites *sp, uint8_t state);  // -1 when no frames
bool deck_claude_agent_step(const DeckAgentSprites *sp, int tag, uint8_t *frame, uint32_t *entered, uint32_t now,
                            uint32_t beat);  // rounds ms[f] to the nearest beat, at least one
bool deck_claude_needy_update(const DeckClaude *c, uint32_t keys[DECK_CLAUDE_MAX_SESSIONS], uint8_t *count);  // true: a new needy row
