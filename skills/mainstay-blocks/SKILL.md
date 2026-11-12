---
name: mainstay-blocks
description: How the editor blocks of a Mainstay CMS site are written and split (block class plus view, containers and items, allow-lists, parts for header and footer, seeding, tests). Use when adding or changing a block, a part, or a block's Blade view on a Mainstay site, or when starting a new Mainstay site.
---

# Mainstay blocks: how they are built and split

Reference implementation: `mainstaycms/mainstaycms.org` (`app/Blocks`, `resources/views/blocks`). The CMS's own Block API is covered by its "Rich text and blocks" doc; this is the site-level convention.

## One block, two files
- Class: `app/Blocks/Card.php`, extends `Mainstay\Content\Block`.
- View: `resources/views/blocks/card.blade.php`, receives `$block`.
- The view name is the handle, `Str::snake(class_basename)`. It is also the `type` stored in content, so renaming a class orphans stored blocks.
- Block data lives in the entry's `content` JSON column. Adding or changing a block field needs no migration.

## Editor metadata on every block
```php
/* A title and a line, under an icon, leading somewhere when it names where. */
#[Icon('block')]
#[Description('A title and a line under an icon, leading to a page or an address.')]
#[Example(['title' => 'A plan, in phases', 'text' => 'Each phase says what it builds.'])]
class Card extends Block
```
- `#[Description]`: one sentence shown in the inserter.
- `#[Example]`: data for a new block; `inner: [Card::class, Card::class, Card::class]` pre-fills a container.
- A `/* why */` comment above the class says what the block is for.

## How blocks are split
- **Container plus item** for anything repeating: `Cards`/`Card`, `Steps`/`Step`, `Tabs`/`Tab`, `Columns`/`Column`, `Menu`/`MenuLink`, `FooterColumn`/`FooterLink`. The container names its item with `#[Blocks([Item::class])]` and may add a layout option (`Cards::$size` is a `Select`, `Steps::$panel` a `Boolean`); the item holds the content.
  ```php
  #[Blocks([Card::class])]
  class Cards extends Block
  {
      #[Select(options: ['cards' => 'Cards', 'tiles' => 'Small tiles'])]
      public string $size = 'cards';
  }
  ```
- **Allow-lists nest.** The entry type lists the top-level blocks (`#[Blocks([...])]` on `Page`); `Section` lists what may sit inside a section; containers list only their item. An editor is only offered what fits.
- **A leaf with no fields of its own to hold** (`Menu`, `SiteHeader`) is an empty class body: attributes only.
- **Site-wide regions are parts.** One wrapper block (`SiteHeader`, `SiteFooter`) inside a `Part` type that allows only that wrapper:
  ```php
  #[Blocks([SiteHeader::class])]
  #[Icon('link')]
  class Navigation extends Part {}
  ```
  The layout prints it with `@part(Navigation::class)`. The header and footer are edited in the Content tab like any page.
- **Share behaviour once a second block needs it**: a trait (`LinksToPage`: `href()` for a block with `page` and `url`, used by `Button`, `FooterLink` and `MenuLink`; `Card` predates it and keeps its own simpler `href()`, so reuse the trait in new blocks), an enum for a shared option list (`Symbol` for icons). Not before.

## Fields
- Required: `#[Text(required: true)] public string $title;`. Optional: nullable type, `public ?string $text;`. A `Select` gets a default value.
- A link is a `#[Relation(to: [Page::class, Doc::class])]` plus a `#[Text(max: 500)] ?string $url` fallback. The relation follows the page's slug; check `->missing` before using it.
- Logic (`href()`, `text()`) lives on the block class; the view only prints.

## Views
- Editable text: `@field($block, 'title')`. Text where backticks mean code: `App\Code\Inline::field($block, 'text')`.
- Children: `@inner($block)`.
- Optional parts print only when filled, or when `Mainstay::marking()` is true (the Content tab's editor is on screen), so an editor can still fill an empty field:
  ```blade
  @if (filled($block->text) || Mainstay::marking())
      <p>{{ Inline::field($block, 'text') }}</p>
  @endif
  ```
- A container with nothing to draw prints nothing (`menu` view trims `Mainstay::inner($block)` and draws no `<nav>` when empty).
- Request context reaches block views through `view()->share('shown', $entry)` in the layout; `App\Http\ActiveLink::state()` uses it for `aria-current`.

## Registration and schema
- Entry and part types: `Mainstay::types([...])` in `AppServiceProvider::boot()`.
- A new entry or part type needs a migration. Production never runs `mainstay:sync`; CI checks migrations against the types with `mainstay:schema:check`.
- Plugins (parts, forms, page builder) are listed in `config/mainstay.php` under `plugins`.

## Seeding
Content is written by seeders through the query layer, blocks as `['block' => X::class, 'data' => [...], 'inner' => [...]]` (`WritesContent` trait). Parts use `Mainstay::saveGlobal($part, ['content' => $blocks], locale: 'en', overrideAccess: true)` (`PartSeeder`), run after the pages they link to. Reseed the dev site to see new content.

## Tests
Feature tests render the page and assert the HTML (`assertSeeInOrder`, `escape: false`). For a part, also test that an edit shows on every page. The suite runs in the podman image; host PHP may lack GD.

## Checklist for a new block
1. Class with metadata and a why-comment.
2. View in `resources/views/blocks/`.
3. Added to the `#[Blocks]` of every parent that may hold it.
4. If repeating: container plus item, not a list field.
5. Seeded where the site shows it.
6. A feature test on its output.
