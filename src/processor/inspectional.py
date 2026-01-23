"""Inspectional reading report generator"""
import json
from pathlib import Path
from datetime import datetime
from typing import Optional
import sys

sys.path.insert(0, str(Path.home() / ".deep-reading"))
from config import OBSIDIAN_SOURCES

def generate_inspectional_report(
    source_id: str,
    title: str,
    author: str,
    url: str,
    duration: int,
    transcript: str,
    ai_analysis: Optional[dict] = None
) -> str:
    """Generate inspectional reading report in Markdown"""

    date_str = datetime.now().strftime("%Y-%m-%d")
    duration_str = f"{duration // 3600}:{(duration % 3600) // 60:02d}:{duration % 60:02d}"

    # If no AI analysis provided, create placeholder
    if not ai_analysis:
        ai_analysis = {
            "summary": "待 AI 分析生成",
            "key_points": ["待分析"],
            "concepts": [],
            "questions": [],
        }

    report = f"""---
source_type: youtube
source_id: {source_id}
source_url: {url}
title: "{title}"
author: "{author}"
duration: "{duration_str}"
date_consumed: {date_str}
tags: []
status: draft
---

# {title}

## 元信息
- **来源**: [YouTube]({url})
- **作者**: {author}
- **时长**: {duration_str}
- **阅读日期**: {date_str}

## 快速摘要

{ai_analysis.get('summary', '待 AI 分析...')}

## 核心观点

"""

    for i, point in enumerate(ai_analysis.get('key_points', []), 1):
        report += f"{i}. {point}\n"

    report += """
## 关键概念

"""

    for concept in ai_analysis.get('concepts', []):
        report += f"- [[{concept}]]\n"

    report += """
## 我的标记

> 播放时添加的标记会显示在这里

## 我的笔记

> 听后感想...

## 思考问题

"""

    for q in ai_analysis.get('questions', []):
        report += f"- {q}\n"

    report += """
## 相关来源

> 相关内容链接...
"""

    return report

def save_report(source_id: str, title: str, content: str) -> Path:
    """Save report to Obsidian vault"""
    OBSIDIAN_SOURCES.mkdir(parents=True, exist_ok=True)

    # Clean title for filename
    safe_title = "".join(c for c in title if c.isalnum() or c in " -_").strip()
    safe_title = safe_title[:100]  # Limit length

    file_path = OBSIDIAN_SOURCES / f"{safe_title}.md"

    with open(file_path, "w") as f:
        f.write(content)

    return file_path
