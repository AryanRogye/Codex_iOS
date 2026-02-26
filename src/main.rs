use std::{
    collections::HashMap,
    fs::File,
    io::{BufRead, BufReader},
    net::SocketAddr,
    path::{Path, PathBuf},
    process::Stdio,
    sync::Arc,
};

use axum::{
    Json, Router,
    extract::{Path as AxumPath, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use chrono::{DateTime, Utc};
use clap::{Args, Parser, Subcommand, ValueEnum};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tokio::{process::Command as TokioCommand, sync::RwLock};
use uuid::Uuid;

#[derive(Debug, Parser)]
#[command(name = "codex-ios-relay")]
#[command(about = "Local macOS relay for iOS chat continuity")]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    Serve(ServeArgs),
    NewToken,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
#[value(rename_all = "lower")]
enum RelayProvider {
    Codex,
    Openai,
}

impl RelayProvider {
    fn label(self) -> &'static str {
        match self {
            RelayProvider::Codex => "codex-default",
            RelayProvider::Openai => "gpt-4.1-mini",
        }
    }
}

#[derive(Debug, Args)]
struct ServeArgs {
    #[arg(long, default_value = "127.0.0.1:8787")]
    bind: String,
    #[arg(long, env = "RELAY_PROVIDER", value_enum, default_value = "codex")]
    provider: RelayProvider,
    #[arg(long, env = "OPENAI_API_KEY")]
    openai_api_key: Option<String>,
    #[arg(long, env = "RELAY_DEFAULT_MODEL")]
    default_model: Option<String>,
    #[arg(long, env = "RELAY_AUTH_TOKEN")]
    auth_token: Option<String>,
    #[arg(long, env = "RELAY_DATA_PATH")]
    data_path: Option<PathBuf>,
    #[arg(long, env = "RELAY_CODEX_BIN", default_value = "codex")]
    codex_bin: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
enum MessageRole {
    User,
    Assistant,
}

impl MessageRole {
    fn as_openai_role(&self) -> &'static str {
        match self {
            MessageRole::User => "user",
            MessageRole::Assistant => "assistant",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredMessage {
    role: MessageRole,
    content: String,
    timestamp: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ThreadRecord {
    id: String,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
    messages: Vec<StoredMessage>,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct Store {
    threads: HashMap<String, ThreadRecord>,
}

#[derive(Debug, Clone)]
struct AppState {
    client: Client,
    provider: RelayProvider,
    openai_api_key: Option<String>,
    codex_bin: String,
    default_model: Option<String>,
    auth_token: Option<String>,
    data_path: PathBuf,
    store: Arc<RwLock<Store>>,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    provider: &'static str,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: String,
}

#[derive(Debug, Serialize)]
struct ThreadSummary {
    id: String,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
    message_count: usize,
    last_message: Option<String>,
}

#[derive(Debug, Serialize)]
struct ChatResponse {
    thread_id: String,
    model: String,
    reply: String,
}

#[derive(Debug, Deserialize)]
struct ChatRequest {
    thread_id: Option<String>,
    message: String,
    model: Option<String>,
}

#[derive(Debug, Serialize)]
struct ThreadResponse {
    id: String,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
    messages: Vec<StoredMessage>,
}

#[derive(Debug, Serialize)]
struct OpenAiChatRequest {
    model: String,
    messages: Vec<OpenAiMessage>,
}

#[derive(Debug, Serialize)]
struct OpenAiMessage {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct OpenAiChatResponse {
    choices: Vec<OpenAiChoice>,
}

#[derive(Debug, Deserialize)]
struct OpenAiChoice {
    message: OpenAiAssistantMessage,
}

#[derive(Debug, Deserialize)]
struct OpenAiAssistantMessage {
    content: String,
}

#[derive(Debug, Deserialize)]
struct OpenAiErrorPayload {
    error: OpenAiErrorBody,
}

#[derive(Debug, Deserialize)]
struct OpenAiErrorBody {
    message: String,
}

#[derive(Debug)]
enum ApiError {
    Unauthorized,
    BadRequest(String),
    NotFound(String),
    Upstream(String),
    Internal(String),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            ApiError::Unauthorized => (StatusCode::UNAUTHORIZED, "Unauthorized".to_string()),
            ApiError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            ApiError::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
            ApiError::Upstream(msg) => (StatusCode::BAD_GATEWAY, msg),
            ApiError::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
        };
        let body = Json(ErrorResponse { error: message });
        (status, body).into_response()
    }
}

struct ProviderChatResult {
    thread_id: String,
    reply: String,
    model: String,
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();
    let default_provider = std::env::var("RELAY_PROVIDER")
        .ok()
        .and_then(|value| RelayProvider::from_str(&value, true).ok())
        .unwrap_or(RelayProvider::Codex);

    match cli.command.unwrap_or(Command::Serve(ServeArgs {
        bind: "127.0.0.1:8787".to_string(),
        provider: default_provider,
        openai_api_key: std::env::var("OPENAI_API_KEY").ok(),
        default_model: std::env::var("RELAY_DEFAULT_MODEL").ok(),
        auth_token: std::env::var("RELAY_AUTH_TOKEN").ok(),
        data_path: std::env::var("RELAY_DATA_PATH").ok().map(PathBuf::from),
        codex_bin: std::env::var("RELAY_CODEX_BIN").unwrap_or_else(|_| "codex".to_string()),
    })) {
        Command::NewToken => {
            println!("{}", Uuid::new_v4());
        }
        Command::Serve(args) => {
            if let Err(err) = run_server(args).await {
                eprintln!("server error: {err}");
                std::process::exit(1);
            }
        }
    }
}

async fn run_server(args: ServeArgs) -> Result<(), String> {
    let openai_api_key = args.openai_api_key.filter(|value| !value.trim().is_empty());
    let default_model = args
        .default_model
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());

    match args.provider {
        RelayProvider::Openai => {
            if openai_api_key.is_none() {
                return Err(
                    "OPENAI_API_KEY (or --openai-api-key) is required when provider=openai"
                        .to_string(),
                );
            }
        }
        RelayProvider::Codex => {
            ensure_codex_ready(&args.codex_bin).await?;
        }
    }

    let bind_addr: SocketAddr = args
        .bind
        .parse()
        .map_err(|err| format!("invalid --bind '{}': {err}", args.bind))?;

    let data_path = args.data_path.unwrap_or_else(default_data_path);
    let store = load_store(&data_path)?;

    if args.auth_token.is_none() {
        eprintln!("warning: running without auth token; set RELAY_AUTH_TOKEN in non-local setups");
    }

    let state = AppState {
        client: Client::new(),
        provider: args.provider,
        openai_api_key,
        codex_bin: args.codex_bin,
        default_model,
        auth_token: args.auth_token,
        data_path,
        store: Arc::new(RwLock::new(store)),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/v1/threads", get(list_threads))
        .route("/v1/threads/{thread_id}", get(get_thread))
        .route("/v1/chat", post(chat))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(bind_addr)
        .await
        .map_err(|err| format!("failed to bind {bind_addr}: {err}"))?;

    println!(
        "relay listening on http://{bind_addr} (provider={})",
        match args.provider {
            RelayProvider::Codex => "codex",
            RelayProvider::Openai => "openai",
        }
    );

    axum::serve(listener, app)
        .await
        .map_err(|err| format!("server failed: {err}"))?;
    Ok(())
}

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    let provider = match state.provider {
        RelayProvider::Codex => "codex",
        RelayProvider::Openai => "openai",
    };
    Json(HealthResponse {
        status: "ok",
        provider,
    })
}

async fn list_threads(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Vec<ThreadSummary>>, ApiError> {
    authorize(&headers, state.auth_token.as_deref())?;

    let mut merged: HashMap<String, ThreadSummary> = HashMap::new();

    {
        let store = state.store.read().await;
        for thread in store.threads.values() {
            merged.insert(
                thread.id.clone(),
                ThreadSummary {
                    id: thread.id.clone(),
                    created_at: thread.created_at,
                    updated_at: thread.updated_at,
                    message_count: thread.messages.len(),
                    last_message: thread
                        .messages
                        .last()
                        .map(|message| message.content.clone()),
                },
            );
        }
    }

    if matches!(state.provider, RelayProvider::Codex) {
        match load_codex_session_summaries() {
            Ok(summaries) => {
                for summary in summaries {
                    merged
                        .entry(summary.id.clone())
                        .and_modify(|existing| merge_thread_summary(existing, &summary))
                        .or_insert(summary);
                }
            }
            Err(err) => {
                eprintln!("warning: failed reading codex sessions: {err}");
            }
        }
    }

    let mut rows = merged.into_values().collect::<Vec<_>>();

    rows.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
    Ok(Json(rows))
}

async fn get_thread(
    AxumPath(thread_id): AxumPath<String>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<ThreadResponse>, ApiError> {
    authorize(&headers, state.auth_token.as_deref())?;
    {
        let store = state.store.read().await;
        if let Some(thread) = store.threads.get(&thread_id) {
            return Ok(Json(ThreadResponse {
                id: thread.id.clone(),
                created_at: thread.created_at,
                updated_at: thread.updated_at,
                messages: thread.messages.clone(),
            }));
        }
    }

    if matches!(state.provider, RelayProvider::Codex) {
        if let Some(thread) = load_codex_session_thread(&thread_id).map_err(ApiError::Internal)? {
            return Ok(Json(ThreadResponse {
                id: thread.id,
                created_at: thread.created_at,
                updated_at: thread.updated_at,
                messages: thread.messages,
            }));
        }
    }

    Err(ApiError::NotFound(format!(
        "thread '{thread_id}' was not found"
    )))
}

async fn chat(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<ChatRequest>,
) -> Result<Json<ChatResponse>, ApiError> {
    authorize(&headers, state.auth_token.as_deref())?;

    let user_message = payload.message.trim().to_string();
    if user_message.is_empty() {
        return Err(ApiError::BadRequest("message cannot be empty".to_string()));
    }

    let requested_thread_id = payload
        .thread_id
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());
    let requested_model = payload
        .model
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .or_else(|| state.default_model.clone());

    let provider_result = match state.provider {
        RelayProvider::Openai => {
            handle_openai_chat(
                &state,
                requested_thread_id.clone(),
                &user_message,
                requested_model,
            )
            .await?
        }
        RelayProvider::Codex => {
            handle_codex_chat(
                &state,
                requested_thread_id.as_deref(),
                &user_message,
                requested_model.as_deref(),
            )
            .await?
        }
    };

    {
        let mut store = state.store.write().await;
        let now = Utc::now();
        let thread = store
            .threads
            .entry(provider_result.thread_id.clone())
            .or_insert_with(|| ThreadRecord {
                id: provider_result.thread_id.clone(),
                created_at: now,
                updated_at: now,
                messages: Vec::new(),
            });

        thread.messages.push(StoredMessage {
            role: MessageRole::User,
            content: user_message,
            timestamp: now,
        });
        thread.messages.push(StoredMessage {
            role: MessageRole::Assistant,
            content: provider_result.reply.clone(),
            timestamp: now,
        });
        thread.updated_at = now;

        persist_store(&state.data_path, &store).map_err(ApiError::Internal)?;
    }

    Ok(Json(ChatResponse {
        thread_id: provider_result.thread_id,
        model: provider_result.model,
        reply: provider_result.reply,
    }))
}

async fn handle_openai_chat(
    state: &AppState,
    requested_thread_id: Option<String>,
    user_message: &str,
    requested_model: Option<String>,
) -> Result<ProviderChatResult, ApiError> {
    let thread_id = requested_thread_id.unwrap_or_else(|| Uuid::new_v4().to_string());
    let model = requested_model.unwrap_or_else(|| RelayProvider::Openai.label().to_string());
    let openai_api_key = state.openai_api_key.as_deref().ok_or_else(|| {
        ApiError::Internal("OPENAI_API_KEY missing for openai provider".to_string())
    })?;

    let prior_messages = {
        let store = state.store.read().await;
        store
            .threads
            .get(&thread_id)
            .map(|thread| thread.messages.clone())
            .unwrap_or_default()
    };

    let mut openai_messages = prior_messages
        .iter()
        .map(|message| OpenAiMessage {
            role: message.role.as_openai_role().to_string(),
            content: message.content.clone(),
        })
        .collect::<Vec<_>>();

    openai_messages.push(OpenAiMessage {
        role: "user".to_string(),
        content: user_message.to_string(),
    });

    let reply = fetch_openai_reply(&state.client, openai_api_key, &model, openai_messages).await?;

    Ok(ProviderChatResult {
        thread_id,
        reply,
        model,
    })
}

async fn handle_codex_chat(
    state: &AppState,
    requested_thread_id: Option<&str>,
    user_message: &str,
    requested_model: Option<&str>,
) -> Result<ProviderChatResult, ApiError> {
    let output = run_codex_exec(
        &state.codex_bin,
        requested_thread_id,
        user_message,
        requested_model,
    )
    .await?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    let parsed = parse_codex_jsonl(&stdout);

    if !output.status.success() {
        let status = output.status;
        let detail = parsed
            .last_error
            .or_else(|| {
                let trimmed = stderr.trim();
                if trimmed.is_empty() {
                    None
                } else {
                    Some(trimmed.to_string())
                }
            })
            .unwrap_or_else(|| "codex command failed".to_string());
        return Err(ApiError::Upstream(format!(
            "codex exec failed ({status}): {detail}"
        )));
    }

    let thread_id = parsed
        .thread_id
        .or_else(|| requested_thread_id.map(|value| value.to_string()))
        .ok_or_else(|| {
            ApiError::Upstream("codex exec succeeded but no thread_id was returned".to_string())
        })?;

    let reply = parsed.reply.ok_or_else(|| {
        ApiError::Upstream(
            "codex exec succeeded but no assistant message was returned. Try again.".to_string(),
        )
    })?;

    Ok(ProviderChatResult {
        thread_id,
        reply,
        model: requested_model
            .map(str::to_string)
            .unwrap_or_else(|| RelayProvider::Codex.label().to_string()),
    })
}

struct ParsedCodexJsonl {
    thread_id: Option<String>,
    reply: Option<String>,
    last_error: Option<String>,
}

fn parse_codex_jsonl(stdout: &str) -> ParsedCodexJsonl {
    let mut thread_id = None;
    let mut reply = None;
    let mut last_error = None;

    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let Ok(value) = serde_json::from_str::<serde_json::Value>(trimmed) else {
            continue;
        };

        let event_type = value
            .get("type")
            .and_then(|entry| entry.as_str())
            .unwrap_or_default();

        match event_type {
            "thread.started" => {
                thread_id = value
                    .get("thread_id")
                    .or_else(|| value.get("threadId"))
                    .and_then(|entry| entry.as_str())
                    .map(|entry| entry.to_string())
                    .or(thread_id);
            }
            "item.completed" => {
                let item = value.get("item");
                let item_type = item
                    .and_then(|entry| entry.get("type"))
                    .and_then(|entry| entry.as_str())
                    .unwrap_or_default();
                if item_type == "agent_message" {
                    if let Some(text) = item
                        .and_then(|entry| entry.get("text"))
                        .and_then(|entry| entry.as_str())
                    {
                        let content = text.trim();
                        if !content.is_empty() {
                            reply = Some(content.to_string());
                        }
                    }
                }
            }
            "error" => {
                last_error = value
                    .get("message")
                    .and_then(|entry| entry.as_str())
                    .map(|entry| entry.to_string())
                    .or(last_error);
            }
            _ => {}
        }
    }

    ParsedCodexJsonl {
        thread_id,
        reply,
        last_error,
    }
}

async fn run_codex_exec(
    codex_bin: &str,
    requested_thread_id: Option<&str>,
    user_message: &str,
    requested_model: Option<&str>,
) -> Result<std::process::Output, ApiError> {
    let mut command = TokioCommand::new(codex_bin);
    command.arg("exec");

    if requested_thread_id.is_some() {
        command.arg("resume").arg("--all");
    }

    command.arg("--json");
    command.arg("--skip-git-repo-check");

    if let Some(model) = requested_model
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        command.arg("-m").arg(model);
    }

    if let Some(thread_id) = requested_thread_id {
        command.arg(thread_id.trim());
    }

    command.arg(user_message);
    command.stdin(Stdio::null());
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());

    command
        .output()
        .await
        .map_err(|err| ApiError::Upstream(format!("failed to spawn codex command: {err}")))
}

async fn ensure_codex_ready(codex_bin: &str) -> Result<(), String> {
    let version_output = TokioCommand::new(codex_bin)
        .arg("--version")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|err| format!("failed to run '{codex_bin} --version': {err}"))?;

    if !version_output.status.success() {
        let stderr = String::from_utf8_lossy(&version_output.stderr);
        return Err(format!("'{codex_bin} --version' failed: {}", stderr.trim()));
    }

    let login_output = TokioCommand::new(codex_bin)
        .arg("login")
        .arg("status")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .map_err(|err| format!("failed to run '{codex_bin} login status': {err}"))?;

    if !login_output.status.success() {
        let stderr = String::from_utf8_lossy(&login_output.stderr);
        return Err(format!(
            "'{codex_bin} login status' failed: {}",
            stderr.trim()
        ));
    }

    let stdout = String::from_utf8_lossy(&login_output.stdout);
    let stderr = String::from_utf8_lossy(&login_output.stderr);
    let combined = format!("{stdout}\n{stderr}");
    if !combined.contains("Logged in") {
        return Err(format!(
            "Codex provider requires a logged-in Codex CLI. Run '{} login'.",
            codex_bin
        ));
    }

    Ok(())
}

#[derive(Debug)]
struct CodexSessionThread {
    id: String,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
    messages: Vec<StoredMessage>,
}

fn merge_thread_summary(existing: &mut ThreadSummary, incoming: &ThreadSummary) {
    if incoming.created_at < existing.created_at {
        existing.created_at = incoming.created_at;
    }
    if incoming.updated_at > existing.updated_at {
        existing.updated_at = incoming.updated_at;
        existing.last_message = incoming.last_message.clone();
    }
    if incoming.message_count > existing.message_count {
        existing.message_count = incoming.message_count;
    }
}

fn load_codex_session_summaries() -> Result<Vec<ThreadSummary>, String> {
    let root = codex_sessions_root();
    if !root.exists() {
        return Ok(Vec::new());
    }

    let mut files = Vec::new();
    collect_jsonl_files(&root, &mut files)?;

    let mut out = Vec::new();
    for path in files {
        if let Some(thread) = parse_codex_session_file(&path)? {
            out.push(ThreadSummary {
                id: thread.id.clone(),
                created_at: thread.created_at,
                updated_at: thread.updated_at,
                message_count: thread.messages.len(),
                last_message: thread
                    .messages
                    .last()
                    .map(|message| message.content.clone()),
            });
        }
    }

    Ok(out)
}

fn load_codex_session_thread(thread_id: &str) -> Result<Option<CodexSessionThread>, String> {
    let root = codex_sessions_root();
    if !root.exists() {
        return Ok(None);
    }

    let mut files = Vec::new();
    collect_jsonl_files(&root, &mut files)?;

    for path in files
        .iter()
        .filter(|path| path.to_string_lossy().contains(thread_id))
    {
        if let Some(thread) = parse_codex_session_file(path)? {
            if thread.id == thread_id {
                return Ok(Some(thread));
            }
        }
    }

    for path in files {
        if path.to_string_lossy().contains(thread_id) {
            continue;
        }
        if let Some(thread) = parse_codex_session_file(&path)? {
            if thread.id == thread_id {
                return Ok(Some(thread));
            }
        }
    }

    Ok(None)
}

fn codex_sessions_root() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".codex")
        .join("sessions")
}

fn collect_jsonl_files(dir: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
    let entries = std::fs::read_dir(dir).map_err(|err| format!("failed reading {dir:?}: {err}"))?;
    for entry in entries {
        let entry = entry.map_err(|err| format!("failed reading dir entry in {dir:?}: {err}"))?;
        let path = entry.path();
        if path.is_dir() {
            collect_jsonl_files(&path, out)?;
            continue;
        }
        if path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| ext.eq_ignore_ascii_case("jsonl"))
            .unwrap_or(false)
        {
            out.push(path);
        }
    }
    Ok(())
}

fn parse_codex_session_file(path: &Path) -> Result<Option<CodexSessionThread>, String> {
    let file = File::open(path).map_err(|err| format!("failed opening {path:?}: {err}"))?;
    let reader = BufReader::new(file);

    let mut thread_id = extract_thread_id_from_path(path);
    let mut created_at: Option<DateTime<Utc>> = None;
    let mut updated_at: Option<DateTime<Utc>> = None;
    let mut messages: Vec<StoredMessage> = Vec::new();

    for line_result in reader.lines() {
        let line = match line_result {
            Ok(line) => line,
            Err(_) => continue,
        };
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        let value = match serde_json::from_str::<serde_json::Value>(line) {
            Ok(value) => value,
            Err(_) => continue,
        };

        let line_timestamp = value
            .get("timestamp")
            .and_then(|entry| entry.as_str())
            .and_then(parse_rfc3339_to_utc);
        if let Some(ts) = line_timestamp {
            created_at = Some(match created_at {
                Some(existing) if existing <= ts => existing,
                _ => ts,
            });
            updated_at = Some(match updated_at {
                Some(existing) if existing >= ts => existing,
                _ => ts,
            });
        }

        let event_type = value
            .get("type")
            .and_then(|entry| entry.as_str())
            .unwrap_or_default();

        if event_type == "session_meta" {
            let payload = value.get("payload");
            if let Some(id) = payload
                .and_then(|entry| entry.get("id"))
                .and_then(|entry| entry.as_str())
            {
                thread_id = Some(id.to_string());
            }
            if let Some(ts) = payload
                .and_then(|entry| entry.get("timestamp"))
                .and_then(|entry| entry.as_str())
                .and_then(parse_rfc3339_to_utc)
            {
                created_at = Some(match created_at {
                    Some(existing) if existing <= ts => existing,
                    _ => ts,
                });
                updated_at = Some(match updated_at {
                    Some(existing) if existing >= ts => existing,
                    _ => ts,
                });
            }
            continue;
        }

        if event_type != "response_item" {
            continue;
        }

        let payload = match value.get("payload") {
            Some(payload) => payload,
            None => continue,
        };
        if payload
            .get("type")
            .and_then(|entry| entry.as_str())
            .unwrap_or_default()
            != "message"
        {
            continue;
        }

        let role = payload
            .get("role")
            .and_then(|entry| entry.as_str())
            .unwrap_or_default();
        let role = match role {
            "user" => MessageRole::User,
            "assistant" => MessageRole::Assistant,
            _ => continue,
        };

        let content = extract_payload_text(payload);
        if content.is_empty() {
            continue;
        }

        let message_time = line_timestamp
            .or(created_at)
            .or(updated_at)
            .unwrap_or_else(Utc::now);

        messages.push(StoredMessage {
            role,
            content,
            timestamp: message_time,
        });
    }

    let Some(thread_id) = thread_id else {
        return Ok(None);
    };

    let created = created_at
        .or_else(|| messages.first().map(|message| message.timestamp))
        .unwrap_or_else(Utc::now);
    let updated = updated_at
        .or_else(|| messages.last().map(|message| message.timestamp))
        .unwrap_or(created);

    Ok(Some(CodexSessionThread {
        id: thread_id,
        created_at: created,
        updated_at: updated,
        messages,
    }))
}

fn extract_payload_text(payload: &serde_json::Value) -> String {
    let mut parts: Vec<String> = Vec::new();

    if let Some(content) = payload.get("content").and_then(|entry| entry.as_array()) {
        for block in content {
            if let Some(text) = block.get("text").and_then(|entry| entry.as_str()) {
                let trimmed = text.trim();
                if !trimmed.is_empty() {
                    parts.push(trimmed.to_string());
                }
            }
        }
    }

    if parts.is_empty() {
        if let Some(text) = payload.get("text").and_then(|entry| entry.as_str()) {
            let trimmed = text.trim();
            if !trimmed.is_empty() {
                parts.push(trimmed.to_string());
            }
        }
    }

    parts.join("\n")
}

fn extract_thread_id_from_path(path: &Path) -> Option<String> {
    let name = path.file_stem()?.to_str()?;
    extract_uuid_from_text(name)
}

fn extract_uuid_from_text(value: &str) -> Option<String> {
    if value.len() < 36 {
        return None;
    }
    for index in (0..=(value.len() - 36)).rev() {
        let candidate = &value[index..index + 36];
        if Uuid::parse_str(candidate).is_ok() {
            return Some(candidate.to_string());
        }
    }
    None
}

fn parse_rfc3339_to_utc(raw: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(raw)
        .ok()
        .map(|value| value.with_timezone(&Utc))
}

async fn fetch_openai_reply(
    client: &Client,
    openai_api_key: &str,
    model: &str,
    messages: Vec<OpenAiMessage>,
) -> Result<String, ApiError> {
    let request = OpenAiChatRequest {
        model: model.to_string(),
        messages,
    };

    let response = client
        .post("https://api.openai.com/v1/chat/completions")
        .bearer_auth(openai_api_key)
        .json(&request)
        .send()
        .await
        .map_err(|err| ApiError::Upstream(format!("OpenAI request failed: {err}")))?;

    let status = response.status();
    if !status.is_success() {
        let body_text = response.text().await.unwrap_or_default();
        if let Ok(parsed) = serde_json::from_str::<OpenAiErrorPayload>(&body_text) {
            return Err(ApiError::Upstream(parsed.error.message));
        }
        return Err(ApiError::Upstream(format!(
            "OpenAI returned {status}: {body_text}"
        )));
    }

    let parsed = response
        .json::<OpenAiChatResponse>()
        .await
        .map_err(|err| ApiError::Upstream(format!("invalid OpenAI response payload: {err}")))?;

    let reply = parsed
        .choices
        .into_iter()
        .next()
        .map(|choice| choice.message.content.trim().to_string())
        .filter(|content| !content.is_empty())
        .ok_or_else(|| ApiError::Upstream("OpenAI returned an empty reply".to_string()))?;

    Ok(reply)
}

fn authorize(headers: &HeaderMap, expected_token: Option<&str>) -> Result<(), ApiError> {
    let Some(expected_token) = expected_token else {
        return Ok(());
    };

    let provided = headers
        .get("x-relay-token")
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|value| !value.is_empty());

    match provided {
        Some(value) if value == expected_token => Ok(()),
        _ => Err(ApiError::Unauthorized),
    }
}

fn default_data_path() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".codex-ios-relay")
        .join("threads.json")
}

fn load_store(path: &Path) -> Result<Store, String> {
    if !path.exists() {
        return Ok(Store::default());
    }

    let data =
        std::fs::read_to_string(path).map_err(|err| format!("failed to read {path:?}: {err}"))?;
    serde_json::from_str(&data).map_err(|err| format!("failed to parse {path:?}: {err}"))
}

fn persist_store(path: &Path, store: &Store) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|err| format!("failed creating directory {parent:?}: {err}"))?;
    }
    let data = serde_json::to_string_pretty(store)
        .map_err(|err| format!("failed to serialize store: {err}"))?;
    std::fs::write(path, data).map_err(|err| format!("failed to write store to {path:?}: {err}"))
}
