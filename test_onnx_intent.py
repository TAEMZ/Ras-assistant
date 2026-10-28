import numpy as np
import onnxruntime as ort
import json

# 1. Load vocabulary
with open('assets/model/intent_vocab.txt', 'r', encoding='utf-8') as f:
    vocab = {line.strip(): i for i, line in enumerate(f)}

# 2. Simple WordPiece Tokenizer
def tokenize(text, max_len=64):
    tokens = ['[CLS]']
    words = text.lower().strip().split()
    for word in words:
        if word in vocab:
            tokens.append(word)
        else:
            # Subword matching
            sub_tokens = []
            start = 0
            while start < len(word):
                end = len(word)
                cur_substr = None
                while start < end:
                    substr = word[start:end]
                    if start > 0:
                        substr = '##' + substr
                    if substr in vocab:
                        cur_substr = substr
                        break
                    end -= 1
                if cur_substr is None:
                    sub_tokens.append('[UNK]')
                    break
                sub_tokens.append(cur_substr)
                start = end
            tokens.extend(sub_tokens)
    tokens.append('[SEP]')
    
    input_ids = [vocab.get(t, vocab['[UNK]']) for t in tokens[:max_len]]
    attention_mask = [1] * len(input_ids)
    token_type_ids = [0] * len(input_ids)
    
    # Pad to max_len
    pad_len = max_len - len(input_ids)
    input_ids += [0] * pad_len
    attention_mask += [0] * pad_len
    token_type_ids += [0] * pad_len
    
    return np.array([input_ids], dtype=np.int64), np.array([attention_mask], dtype=np.int64), np.array([token_type_ids], dtype=np.int64)

# 3. Initialize ONNX Session
session = ort.InferenceSession('assets/model/intent_embed.onnx')

def embed(text):
    input_ids, attention_mask, token_type_ids = tokenize(text)
    outputs = session.run(['last_hidden_state'], {
        'input_ids': input_ids,
        'attention_mask': attention_mask,
        'token_type_ids': token_type_ids
    })
    last_hidden_state = outputs[0]  # [1, seq_len, 384]
    
    # Mean pooling
    mask_expanded = np.expand_dims(attention_mask, -1).astype(np.float32)
    sum_embeddings = np.sum(last_hidden_state * mask_expanded, axis=1)
    sum_mask = np.clip(np.sum(mask_expanded, axis=1), a_min=1e-9, a_max=None)
    mean_pooled = sum_embeddings / sum_mask
    
    # L2 normalize
    norm = np.linalg.norm(mean_pooled, axis=1, keepdims=True)
    return mean_pooled / np.clip(norm, a_min=1e-9, a_max=None)

# 4. Action Anchors (exact same concept as tested in Colab)
ACTIONS = {
    "search_files": [
        "find my downloaded files", "show my pdf documents", "search photos",
        "find receipt", "find pdf files", "search files on device", "mp3 files",
        "find audio files", "search music", "how many files"
    ],
    "launch_app": [
        "open app", "launch application", "start telegram", "open whatsapp",
        "launch chrome", "open settings"
    ],
    "call_contact": [
        "call contact", "make a phone call", "dial phone number", "call someone right now"
    ],
    "device_status": [
        "check battery level", "how much storage is left", "battery percentage",
        "available disk space", "phone status"
    ],
    "joke_and_banter": [
        "tell me a joke", "make me laugh", "how are you doing", "hello ras"
    ]
}

# Precompute anchor vectors
action_vectors = {}
for act, phrases in ACTIONS.items():
    phrase_vecs = np.vstack([embed(p) for p in phrases])
    mean_vec = np.mean(phrase_vecs, axis=0, keepdims=True)
    action_vectors[act] = mean_vec / np.linalg.norm(mean_vec)

def classify(query):
    q_vec = embed(query)
    scores = {}
    for act, a_vec in action_vectors.items():
        score = float(np.dot(q_vec, a_vec.T)[0, 0])
        scores[act] = score
    sorted_scores = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    best_act, best_score = sorted_scores[0]
    print(f"\n[Query]: \"{query}\"")
    print(f"  -> Matched Action: {best_act.upper()} (Confidence: {best_score:.4f})")
    for act, sc in sorted_scores:
        print(f"     • {act}: {sc:.4f}")
    return best_act, best_score

print("=== RUNNING LOCAL ONNX SEMANTIC CLASSIFICATION BENCHMARK ===")
classify("Find my downloaded receipt PDF")
classify("how many pdf files in my device")
classify("pdf search")
classify("mp3 files")
classify("search for mp3 music")
classify("Open Telegram app")
classify("Call Abebe right now")
classify("How much battery do I have left?")
classify("Tell me a funny joke")
