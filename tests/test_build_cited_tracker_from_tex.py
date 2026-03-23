import json
from pathlib import Path

from tools.latex import _handle_build_cited_tracker_from_tex


def _write_bib(path: Path):
    path.write_text(
        """@article{Spalart2009,
  title={Hybrid methods},
  doi={10.1016/j.jcp.2009.01.001}
}

@article{Shur2008,
  title={Detached eddy simulation},
  doi={10.1016/j.ijhff.2008.02.001}
}

@article{NoDoi2024,
  title={Missing DOI entry}
}
""",
        encoding="utf-8",
    )


def _read_jsonl(path: Path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def test_build_tracker_writes_one_row_per_citation_and_numeric_section(tmp_path):
    tex = tmp_path / "02-methods.tex"
    bib = tmp_path / "refs.bib"
    output = tmp_path / "references" / "cited_tracker.jsonl"

    _write_bib(bib)
    tex.write_text(
        r"""
        \begin{document}
        Hybrid RANS-LES methods reduce computational cost compared to wall-resolved LES \citep{Spalart2009,Shur2008}.
        \end{document}
        """,
        encoding="utf-8",
    )

    result = _handle_build_cited_tracker_from_tex({
        "tex_file": str(tex),
        "bib_file": str(bib),
        "output_file": str(output),
    })

    assert result["success"] is True
    assert result["section"] == "2"
    assert result["rows_written"] == 2

    rows = _read_jsonl(output)
    assert len(rows) == 2
    assert {row["doi"] for row in rows} == {
        "10.1016/j.jcp.2009.01.001",
        "10.1016/j.ijhff.2008.02.001",
    }
    assert all(row["section"] == "2" for row in rows)
    assert all(row["role"] == "support" for row in rows)
    assert all("\\cite" not in row["claim"] for row in rows)


def test_build_tracker_uses_filename_stem_for_non_numeric_sections(tmp_path):
    tex = tmp_path / "introduction.tex"
    bib = tmp_path / "refs.bib"
    output = tmp_path / "references" / "cited_tracker.jsonl"

    _write_bib(bib)
    tex.write_text(
        r"Introductory background motivates the later analysis \cite{Spalart2009}.",
        encoding="utf-8",
    )

    result = _handle_build_cited_tracker_from_tex({
        "tex_file": str(tex),
        "bib_file": str(bib),
        "output_file": str(output),
    })

    assert result["success"] is True
    assert result["section"] == "introduction"

    rows = _read_jsonl(output)
    assert len(rows) == 1
    assert rows[0]["section"] == "introduction"


def test_build_tracker_reports_missing_bib_and_missing_doi_keys(tmp_path):
    tex = tmp_path / "03-results.tex"
    bib = tmp_path / "refs.bib"
    output = tmp_path / "references" / "cited_tracker.jsonl"

    _write_bib(bib)
    tex.write_text(
        r"""
        This sentence cites a missing key \cite{Missing2026}.
        This sentence cites a bib entry without DOI \cite{NoDoi2024}.
        """,
        encoding="utf-8",
    )

    result = _handle_build_cited_tracker_from_tex({
        "tex_file": str(tex),
        "bib_file": str(bib),
        "output_file": str(output),
    })

    assert result["success"] is True
    assert result["rows_written"] == 0
    assert result["skipped_missing_bib_keys"] == ["Missing2026"]
    assert result["skipped_missing_doi_keys"] == ["NoDoi2024"]
    assert _read_jsonl(output) == []


def test_build_tracker_replace_section_only_rewrites_matching_section(tmp_path):
    tex = tmp_path / "02-methods.tex"
    bib = tmp_path / "refs.bib"
    output = tmp_path / "references" / "cited_tracker.jsonl"

    _write_bib(bib)
    tex.write_text(
        r"Updated methods claim \cite{Spalart2009}.",
        encoding="utf-8",
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        "\n".join([
            json.dumps({"doi": "10.old/section2", "section": "2", "role": "support", "claim": "old"}),
            json.dumps({"doi": "10.keep/section3", "section": "3", "role": "support", "claim": "keep"}),
        ]) + "\n",
        encoding="utf-8",
    )

    result = _handle_build_cited_tracker_from_tex({
        "tex_file": str(tex),
        "bib_file": str(bib),
        "output_file": str(output),
        "replace_section": True,
    })

    assert result["success"] is True
    rows = _read_jsonl(output)
    assert len(rows) == 2
    assert {row["section"] for row in rows} == {"2", "3"}
    section2 = [row for row in rows if row["section"] == "2"]
    assert len(section2) == 1
    assert section2[0]["doi"] == "10.1016/j.jcp.2009.01.001"
    assert any(row["doi"] == "10.keep/section3" for row in rows)
