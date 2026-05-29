---
name: claude-api-go
description: Claude API / Anthropic Go SDK usage patterns, prompt caching, streaming, tool use, and model selection for Go applications.
trigger: /claude-api-go
---

# Claude API — Go SDK Patterns

## Setup

```bash
go get github.com/anthropics/anthropic-sdk-go
```

```go
import "github.com/anthropics/anthropic-sdk-go"

client := anthropic.NewClient()  // reads ANTHROPIC_API_KEY from env
```

## Basic Message

```go
msg, err := client.Messages.New(ctx, anthropic.MessageNewParams{
    Model:     anthropic.ModelClaude3_5SonnetLatest,
    MaxTokens: 1024,
    Messages: []anthropic.MessageParam{
        anthropic.NewUserMessage(anthropic.NewTextBlock("Hello")),
    },
})
if err != nil {
    return fmt.Errorf("claude: %w", err)
}
fmt.Println(msg.Content[0].Text)
```

## Prompt Caching (Required for large contexts)

```go
// Mark reusable content with cache_control
systemBlock := anthropic.TextBlockParam{
    Type: anthropic.F(anthropic.TextBlockParamTypeText),
    Text: anthropic.F(longSystemPrompt),
    CacheControl: anthropic.F[anthropic.CacheControlEphemeralParam](
        anthropic.CacheControlEphemeralParam{
            Type: anthropic.F(anthropic.CacheControlEphemeralParamTypEphemeral),
        },
    ),
}

msg, err := client.Messages.New(ctx, anthropic.MessageNewParams{
    Model:    anthropic.ModelClaude3_5SonnetLatest,
    MaxTokens: 1024,
    System:   []anthropic.TextBlockParam{systemBlock},
    Messages: messages,
})
```

Cache rules:
- Minimum 1024 tokens (Haiku) / 2048 tokens (Sonnet/Opus)
- TTL: 5 minutes (refreshed on cache hit)
- Cost: 25% write / 10% read (vs 100% base)

## Streaming

```go
stream := client.Messages.NewStreaming(ctx, anthropic.MessageNewParams{
    Model:     anthropic.ModelClaude3_5SonnetLatest,
    MaxTokens: 2048,
    Messages:  messages,
})

for stream.Next() {
    event := stream.Current()
    switch delta := event.Delta.(type) {
    case anthropic.ContentBlockDeltaEventDelta:
        if delta.Type == anthropic.ContentBlockDeltaEventDeltaTypeTextDelta {
            fmt.Print(delta.Text)
        }
    }
}
if err := stream.Err(); err != nil {
    return fmt.Errorf("stream: %w", err)
}
```

## Tool Use (Agentic Loop)

```go
tools := []anthropic.ToolParam{
    {
        Name:        anthropic.F("get_weather"),
        Description: anthropic.F("Get current weather for a location"),
        InputSchema: anthropic.F(anthropic.ToolInputSchemaParam{
            Type: anthropic.F(anthropic.ToolInputSchemaParamTypeObject),
            Properties: anthropic.F(map[string]interface{}{
                "location": map[string]string{
                    "type":        "string",
                    "description": "City name",
                },
            }),
            Required: anthropic.F([]string{"location"}),
        }),
    },
}

for {
    msg, _ := client.Messages.New(ctx, anthropic.MessageNewParams{
        Model:    anthropic.ModelClaude3_5SonnetLatest,
        Tools:    tools,
        Messages: messages,
    })

    if msg.StopReason == anthropic.MessageStopReasonEndTurn {
        break
    }

    messages = append(messages, msg.ToParam())
    var toolResults []anthropic.ToolResultBlockParam
    for _, block := range msg.Content {
        if block.Type == anthropic.ContentBlockTypeToolUse {
            result := callTool(block.Name, block.Input)
            toolResults = append(toolResults, anthropic.NewToolResultBlock(block.ID, result, false))
        }
    }
    messages = append(messages, anthropic.NewToolResultMessage(toolResults...))
}
```

## Model Selection

| Use Case | Model |
|----------|-------|
| Complex reasoning, coding | `anthropic.ModelClaude_Opus_4_7` |
| Balanced cost/performance | `anthropic.ModelClaude_Sonnet_4_6` |
| Fast, simple tasks | `anthropic.ModelClaude_Haiku_4_5_20251001` |

## Error Handling

```go
msg, err := client.Messages.New(ctx, params)
var apiErr *anthropic.Error
if errors.As(err, &apiErr) {
    switch apiErr.StatusCode {
    case 429:
        // rate limited — exponential backoff
    case 529:
        // overloaded — retry with backoff
    }
}
```

## Anti-Patterns

- Not caching large system prompts (wastes tokens on every call)
- `MaxTokens` set too low (causes mid-response truncation)
- Ignoring `StopReason` in tool use loop (may miss tool calls)
- Hardcoding model string without constant (breaks on deprecation)
