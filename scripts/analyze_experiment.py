"""
实验分析脚本：关键词分类 + system_fingerprint 统计

用法：
    python analyze_experiment.py <实验目录>

实验目录应包含：
    batch_001.md              # 每轮实验报告
    batch_001_meta.json       # 元数据（含 system_fingerprint）
    _summary.md               # 汇总报告（可选）

输出：
    终端打印对照表 + 异常率统计
"""

import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

# ── 关键词分类表（直接复制自调研层方案） ──

CATEGORIES = {
    "教程": ["教程", "如何", "步骤", "方法", "指南", "详解", "实操", "技巧"],
    "知识": ["物理", "数学", "化学", "地理", "历史", "哲学", "生物", "天文"],
    "代码": ["代码", "编程", "函数", "变量", "print(", "def ", "class ", "import "],
    "角色": ["扮演", "角色", "设定", "情境"],
    "解析": ["分析", "解释", "含义", "意思", "意义", "本质", "根源"],
    "叙事": ["故事", "从前", "曾经", "有一天", "传说", "很久以前"],
}


def classify_output(content: str) -> dict:
    """关键词分类。返回 {trigger, category, keywords_found}。"""
    result = {"trigger": 0, "category": "normal", "keywords_found": []}
    if len(content) <= 50:
        return result
    for cat_name, keywords in CATEGORIES.items():
        for kw in keywords:
            if kw in content:
                result["trigger"] = 1
                result["category"] = cat_name
                result["keywords_found"] = [kw]
                return result
    result["trigger"] = 2
    result["category"] = "uncertain"
    return result


def extract_response_content(md_path: Path) -> str:
    """从实验 .md 文件的 ## response 段提取 content。"""
    text = md_path.read_text(encoding="utf-8")
    # 找到 ## response 后面的 ```json...``` 块
    match = re.search(r"## response\n\n```json\n(.+?)\n```", text, re.DOTALL)
    if not match:
        return ""
    try:
        data = json.loads(match.group(1))
        choices = data.get("choices", [])
        if choices:
            return choices[0].get("message", {}).get("content", "")
    except json.JSONDecodeError:
        return ""
    return ""


def extract_reasoning_content(md_path: Path) -> str:
    """从实验 .md 文件的 ## response 段提取 reasoning_content。"""
    text = md_path.read_text(encoding="utf-8")
    match = re.search(r"## response\n\n```json\n(.+?)\n```", text, re.DOTALL)
    if not match:
        return ""
    try:
        data = json.loads(match.group(1))
        choices = data.get("choices", [])
        if choices:
            return choices[0].get("message", {}).get("reasoning_content", "")
    except json.JSONDecodeError:
        return ""
    return ""


def load_meta(meta_path: Path) -> dict:
    """加载 _meta.json 文件。"""
    if meta_path.exists():
        try:
            return json.loads(meta_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return {}
    return {}


def analyze_directory(dir_path: Path):
    """分析实验目录，输出对照表。"""
    if not dir_path.exists():
        print(f"[错误] 目录不存在: {dir_path}")
        return

    # 收集所有实验文件
    md_files = sorted(dir_path.glob("batch_*.md"))
    meta_files = {p.stem.replace("_meta", ""): p for p in dir_path.glob("*_meta.json")}

    if not md_files:
        print(f"[错误] 目录中没有 batch_*.md 文件: {dir_path}")
        return

    results = []
    for md in md_files:
        stem = md.stem  # e.g. batch_001
        meta = load_meta(meta_files.get(stem, dir_path / f"{stem}_meta.json"))

        content = extract_response_content(md)
        reasoning = extract_reasoning_content(md)
        cls = classify_output(content)

        fp = meta.get("system_fingerprint", "")
        reasoning_tokens = meta.get("reasoning_tokens", 0)

        results.append({
            "file": md.name,
            "content_len": len(content),
            "reasoning_len": len(reasoning),
            "reasoning_tokens": reasoning_tokens,
            "trigger": cls["trigger"],
            "category": cls["category"],
            "fingerprint": fp,
            "content_preview": content[:60].replace("\n", " "),
        })

    # ── 输出对照表 ──
    print(f"\n{'='*100}")
    print(f"  分析报告: {dir_path}")
    print(f"  样本数: {len(results)}")
    print(f"{'='*100}\n")

    print(f"{'文件':<22} {'内容长度':<8} {'推理长度':<8} {'推理token':<10} {'触发':<6} {'分类':<8} {'指纹':<50}")
    print(f"{'-'*22} {'-'*8} {'-'*8} {'-'*10} {'-'*6} {'-'*8} {'-'*50}")
    for r in results:
        trigger_str = {0: "正常", 1: "触发", 2: "待定"}[r["trigger"]]
        fp_short = r["fingerprint"][:48] if r["fingerprint"] else "(无)"
        print(f"{r['file']:<22} {r['content_len']:<8} {r['reasoning_len']:<8} {r['reasoning_tokens']:<10} {trigger_str:<6} {r['category']:<8} {fp_short}")

    # ── 异常率统计 ──
    total = len(results)
    triggered = sum(1 for r in results if r["trigger"] == 1)
    uncertain = sum(1 for r in results if r["trigger"] == 2)
    normal = total - triggered - uncertain
    rate = triggered / max(1, total - uncertain) * 100

    print(f"\n{'='*100}")
    print(f"  异常率统计")
    print(f"{'='*100}")
    print(f"  总样本: {total}")
    print(f"  触发:   {triggered} ({triggered/total*100:.1f}%)")
    print(f"  正常:   {normal} ({normal/total*100:.1f}%)")
    print(f"  待定:   {uncertain} ({uncertain/total*100:.1f}%)")
    print(f"  异常率: {rate:.1f}%（触发数 / (总样本 - 待定数)）")

    # ── fingerprint 分布 ──
    fps = [r["fingerprint"] for r in results if r["fingerprint"]]
    if fps:
        fp_counter = Counter(fps)
        print(f"\n{'='*100}")
        print(f"  system_fingerprint 分布")
        print(f"{'='*100}")
        for fp, count in fp_counter.most_common():
            print(f"  {count:>4} 次  {fp}")
        print(f"  不同 fingerprint 数: {len(fp_counter)}")
    else:
        print(f"\n  (无 fingerprint 数据)")

    # ── 触发样本详情 ──
    triggered_samples = [r for r in results if r["trigger"] == 1]
    if triggered_samples:
        print(f"\n{'='*100}")
        print(f"  触发样本预览")
        print(f"{'='*100}")
        for r in triggered_samples[:10]:
            print(f"  [{r['file']}] ({r['category']})")
            print(f"  {r['content_preview']}")
            print()

    # ── 待定样本详情 ──
    uncertain_samples = [r for r in results if r["trigger"] == 2]
    if uncertain_samples:
        print(f"\n{'='*100}")
        print(f"  待定样本（需人工研判）— 列表")
        print(f"{'='*100}")
        for r in uncertain_samples:
            print(f"  [{r['file']}] ({r['content_len']} 字) {r['content_preview']}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python analyze_experiment.py <实验目录>")
        print("示例: python analyze_experiment.py user://experiments/batch_20260516_0641_思考2")
        sys.exit(1)

    dir_path = Path(sys.argv[1])
    analyze_directory(dir_path)
