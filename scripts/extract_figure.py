#!/usr/bin/env python3
"""
extract_figure.py — Extract figures from PDF files using PyMuPDF.

Extracts images from PDF pages for use as reference figures in the survey.
Can extract all images from a PDF or target specific pages.

Usage:
  python scripts/extract_figure.py papers/Litteken*.pdf --output AI-generated-outputs/thread-01-survey/01-scout/scout-materials/figures/
  python scripts/extract_figure.py papers/Valle*.pdf --pages 3-5 --output figures/
  python scripts/extract_figure.py papers/Zhang*.pdf --list   # List images without extracting

Dependencies: pymupdf (pip install pymupdf)
"""

import argparse
import sys
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError:
    print("Error: PyMuPDF not installed. Run: pip install pymupdf", file=sys.stderr)
    sys.exit(1)


def parse_page_range(page_str: str, total_pages: int) -> list:
    """Parse page range string like '1-5' or '3' or '1,3,5' into 0-indexed page numbers."""
    pages = []
    for part in page_str.split(","):
        part = part.strip()
        if "-" in part:
            start, end = part.split("-", 1)
            start = max(1, int(start))
            end = min(total_pages, int(end))
            pages.extend(range(start - 1, end))
        else:
            page_num = int(part) - 1
            if 0 <= page_num < total_pages:
                pages.append(page_num)
    return sorted(set(pages))


def list_images(pdf_path: str):
    """List all images in a PDF without extracting."""
    doc = fitz.open(pdf_path)
    print(f"\nImages in: {pdf_path}")
    print(f"Total pages: {len(doc)}")
    print(f"{'='*60}")

    total_images = 0
    for page_num in range(len(doc)):
        page = doc[page_num]
        images = page.get_images(full=True)
        if images:
            print(f"\nPage {page_num + 1}: {len(images)} image(s)")
            for i, img in enumerate(images):
                xref = img[0]
                base_image = doc.extract_image(xref)
                print(f"  [{i+1}] {base_image['width']}x{base_image['height']} "
                      f"({base_image['ext']}, {len(base_image['image'])//1024}KB)")
            total_images += len(images)

    print(f"\n{'='*60}")
    print(f"Total: {total_images} images across {len(doc)} pages")
    doc.close()


def extract_images(pdf_path: str, output_dir: str, pages: list = None,
                   min_width: int = 100, min_height: int = 100):
    """Extract images from a PDF to the output directory."""
    doc = fitz.open(pdf_path)
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    pdf_stem = Path(pdf_path).stem
    # Clean up filename for use as prefix
    prefix = pdf_stem.replace(" ", "_")[:40]

    if pages is None:
        pages = list(range(len(doc)))

    extracted = 0
    skipped = 0

    for page_num in pages:
        if page_num >= len(doc):
            print(f"  Warning: Page {page_num + 1} doesn't exist (PDF has {len(doc)} pages)", file=sys.stderr)
            continue

        page = doc[page_num]
        images = page.get_images(full=True)

        for i, img in enumerate(images):
            xref = img[0]
            base_image = doc.extract_image(xref)
            width = base_image["width"]
            height = base_image["height"]

            # Skip tiny images (icons, bullets, etc.)
            if width < min_width or height < min_height:
                skipped += 1
                continue

            ext = base_image["ext"]
            image_bytes = base_image["image"]

            filename = f"{prefix}_p{page_num+1}_img{i+1}.{ext}"
            filepath = output_path / filename

            with open(filepath, "wb") as f:
                f.write(image_bytes)

            print(f"  Extracted: {filename} ({width}x{height}, {len(image_bytes)//1024}KB)")
            extracted += 1

    doc.close()
    print(f"\nDone: {extracted} images extracted, {skipped} small images skipped")
    print(f"Output: {output_path}")
    return extracted


def extract_page_as_image(pdf_path: str, page_num: int, output_path: str, dpi: int = 200):
    """Render a full PDF page as a high-res image (for figures that span the whole page)."""
    doc = fitz.open(pdf_path)
    if page_num < 1 or page_num > len(doc):
        print(f"Error: Page {page_num} doesn't exist (PDF has {len(doc)} pages)", file=sys.stderr)
        doc.close()
        return False

    page = doc[page_num - 1]
    zoom = dpi / 72
    mat = fitz.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=mat)

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    pix.save(str(output))
    print(f"  Rendered page {page_num} at {dpi}dpi: {output} ({pix.width}x{pix.height})")
    doc.close()
    return True


def main():
    parser = argparse.ArgumentParser(description="Extract figures from PDF files")
    parser.add_argument("pdf", help="Path to the PDF file")
    parser.add_argument("--output", "-o", default="figures/", help="Output directory (default: figures/)")
    parser.add_argument("--pages", help="Page range to extract from (e.g., '1-5', '3', '1,3,5')")
    parser.add_argument("--list", action="store_true", help="List images without extracting")
    parser.add_argument("--render-page", type=int, help="Render a specific page as a full image")
    parser.add_argument("--dpi", type=int, default=200, help="DPI for page rendering (default: 200)")
    parser.add_argument("--min-width", type=int, default=100, help="Min image width to extract (default: 100)")
    parser.add_argument("--min-height", type=int, default=100, help="Min image height to extract (default: 100)")

    args = parser.parse_args()

    pdf_path = Path(args.pdf)
    if not pdf_path.exists():
        print(f"Error: {args.pdf} not found", file=sys.stderr)
        sys.exit(1)

    if args.list:
        list_images(str(pdf_path))
    elif args.render_page:
        pdf_stem = pdf_path.stem.replace(" ", "_")[:40]
        output_file = Path(args.output) / f"{pdf_stem}_p{args.render_page}.png"
        success = extract_page_as_image(str(pdf_path), args.render_page, str(output_file), args.dpi)
        if not success:
            sys.exit(1)
    else:
        pages = None
        if args.pages:
            doc = fitz.open(str(pdf_path))
            total = len(doc)
            doc.close()
            pages = parse_page_range(args.pages, total)
        extract_images(str(pdf_path), args.output, pages, args.min_width, args.min_height)


if __name__ == "__main__":
    main()
