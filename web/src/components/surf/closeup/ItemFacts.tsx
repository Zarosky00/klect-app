import { calendarDate } from '@/lib/format';
import { cn } from '@/lib/cn';
import type { CloseupItemDetail } from '@/lib/types';

/**
 * The catalogue card. Everything the collector bothered to record, and nothing
 * they did not — an empty field is omitted rather than rendered as "—", because
 * a wall of dashes reads like a broken form.
 */

function money(value: number | null, currency: string | null): string | null {
  if (value === null) return null;
  if (!currency) return String(value);
  try {
    return new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(value);
  } catch {
    return `${currency} ${value}`;
  }
}

function attributeLabel(key: string): string {
  return key
    .replace(/[_-]+/g, ' ')
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

function attributeValue(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  return null;
}

export function ItemFacts({
  item,
  className,
}: {
  item: CloseupItemDetail;
  className?: string;
}) {
  const facts: Array<{ term: string; value: string }> = [];

  const push = (term: string, value: string | number | null | undefined): void => {
    if (value === null || value === undefined || value === '') return;
    facts.push({ term, value: String(value) });
  };

  push('Brand', item.brand);
  push('Model', item.model);
  push('Year', item.year);
  push('Rarity', item.rarity);
  push('Condition', item.condition);
  push('Paid', money(item.purchase_price, item.currency));
  push('Acquired', item.acquisition_date ? calendarDate(item.acquisition_date) : null);
  push('From', item.acquisition_place);
  push('Added', calendarDate(item.created_at));

  for (const [key, raw] of Object.entries(item.attributes ?? {})) {
    const value = attributeValue(raw);
    if (value) push(attributeLabel(key), value);
  }

  if (facts.length === 0) return null;

  return (
    <dl
      className={cn(
        'grid grid-cols-2 gap-x-4 gap-y-3 border-t border-line-subtle pt-4',
        className,
      )}
    >
      {facts.map((fact) => (
        <div key={fact.term} className="min-w-0">
          <dt className="text-micro uppercase tracking-widest text-ink-3">{fact.term}</dt>
          <dd className="mt-0.5 break-words text-callout text-ink">{fact.value}</dd>
        </div>
      ))}
    </dl>
  );
}
