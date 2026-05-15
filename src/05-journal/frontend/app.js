const root = document.getElementById('app');

function layout(content) {
  root.innerHTML = `
    <main>
      <h1>Journal App</h1>
      <nav>
        <a href="#/new">New Entry</a>
        <a href="#/list">Entry List</a>
      </nav>
      <section>${content}</section>
    </main>`;
}

async function renderList() {
  const res = await fetch('/journal/api/entries');
  const items = await res.json();
  layout(`
    <h2>Entries</h2>
    <ul>
      ${items.map(item => {
        const escapedTitle = item.title.replace(/[&<>"'`=\/]/g, s => ({
          '&': '&amp;',
          '<': '&lt;',
          '>': '&gt;',
          '"': '&quot;',
          "'": '&#39;',
          '`': '&#96;',
          '=': '&#61;',
          '/': '&#47;'
        })[s]);
        return `<li><a href="#/entry/${item.id}">${escapedTitle}</a> <small>${new Date(item.createdAt).toLocaleString()}</small></li>`;
      }).join('')}
    </ul>
  `);
}

async function renderEntry(id) {
  const res = await fetch(`/journal/api/entries/${id}`);
  if (res.status === 404) {
    layout('<p>Entry not found.</p>');
    return;
  }
  const item = await res.json();
  layout(`
    <h2>${item.title}</h2>
    <p><small>${new Date(item.createdAt).toLocaleString()}</small></p>
    <article class="entry-body"></article>
  `);
  document.querySelector('.entry-body').textContent = item.body;
}

function renderNew() {
  layout(`
    <h2>New Entry</h2>
    <form id="entryForm">
      <label>Title <input name="title" required /></label>
      <label>Body <textarea name="body" rows="12" required></textarea></label>
      <button type="submit">Save</button>
    </form>
  `);
  document.getElementById('entryForm').addEventListener('submit', async (event) => {
    event.preventDefault();
    const form = new FormData(event.target);
    const payload = {
      title: form.get('title'),
      body: form.get('body')
    };
    const res = await fetch('/journal/api/entries', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await res.json();
    location.hash = `#/entry/${data.id}`;
  });
}

async function router() {
  const hash = location.hash || '#/list';
  if (hash === '#/new') return renderNew();
  if (hash === '#/list') return renderList();
  const match = hash.match(/^#\/entry\/(\d+)$/);
  if (match) return renderEntry(match[1]);
  return renderList();
}

window.addEventListener('hashchange', router);
router();
