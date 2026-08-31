/** One page of a cursor-paginated API. */
export type Page<T> = { items: T[]; next_cursor: string | null };

/**
 * Walks a cursor-paginated API and yields records one at a time, so the caller
 * never sees pages and memory stays flat regardless of total size.
 */
export async function* paginate<T>(
  fetchPage: (cursor?: string) => Promise<Page<T>>,
  maxPages = 10_000,
): AsyncGenerator<T> {
  let cursor: string | undefined;
  let pages = 0;
  const seen = new Set<string>();

  do {
    if (++pages > maxPages) throw new Error(`paginate: exceeded ${maxPages} pages`);
    const page = await fetchPage(cursor);
    for (const item of page.items) yield item;

    const next = page.next_cursor ?? undefined;
    // A vendor repeating a cursor would otherwise loop forever.
    if (next !== undefined) {
      if (seen.has(next)) throw new Error(`paginate: repeated cursor ${next}`);
      seen.add(next);
    }
    cursor = next;
  } while (cursor);
}
