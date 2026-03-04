import './style.css';

const API_BASE = 'https://veriv.tunasestaindonesia.com';

const state = {
  isLoggedIn: false,
  user: null,
  logs: [],
  historyDates: [],
  activeView: 'dashboard', // dashboard, history, users
};

// --- API Implementation ---
async function apiCall(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Request failed');
  }
  return response.json();
}

// --- Views Rendering ---

function renderLogin() {
  const app = document.querySelector('#app');
  app.innerHTML = `
    <div class="glass fade-in" style="max-width: 400px; margin: 5rem auto; padding: 2.5rem;">
      <div style="text-align: center; margin-bottom: 2rem;">
        <i class="fas fa-shield-halved" style="font-size: 3rem; color: var(--primary); margin-bottom: 1rem;"></i>
        <h1>Admin Login</h1>
        <p style="color: var(--secondary);">Server Verifikasi Pulang</p>
      </div>
      
      <form id="login-form">
        <div class="input-group">
          <label>Username</label>
          <input type="text" id="username" placeholder="admin" required value="admin">
        </div>
        <div class="input-group">
          <label>Password</label>
          <input type="password" id="password" required value="admin123">
        </div>
        <button type="submit" class="btn btn-primary" style="width: 100%; justify-content: center;">
          LOGIN <i class="fas fa-arrow-right"></i>
        </button>
      </form>
    </div>
  `;

  document.querySelector('#login-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const username = document.querySelector('#username').value;
    const password = document.querySelector('#password').value;

    try {
      const data = await apiCall('/admin/login', {
        method: 'POST',
        body: JSON.stringify({ username, password }),
      });
      state.isLoggedIn = true;
      state.user = data;
      renderApp();
    } catch (err) {
      alert(err.message);
    }
  });
}

function renderSidebar() {
  return `
    <div class="glass" style="padding: 1.5rem; display: flex; flex-direction: column; gap: 0.5rem; height: auto;">
      <div style="margin-bottom: 2rem; display: flex; align-items: center; gap: 1rem;">
        <div style="background: var(--primary); padding: 0.5rem; border-radius: 8px;">
          <i class="fas fa-server" style="color: white;"></i>
        </div>
        <div>
          <div style="font-weight: 700; font-size: 1.1rem;">Verifikasi</div>
          <div style="font-size: 0.75rem; color: var(--secondary);">Web Operator</div>
        </div>
      </div>
      
      <button class="btn ${state.activeView === 'dashboard' ? 'btn-primary' : ''}" style="width: 100%; justify-content: flex-start;" onclick="switchView('dashboard')">
        <i class="fas fa-chart-line"></i> Dashboard
      </button>
      <button class="btn ${state.activeView === 'history' ? 'btn-primary' : ''}" style="width: 100%; justify-content: flex-start;" onclick="switchView('history')">
        <i class="fas fa-clock-rotate-left"></i> History
      </button>
      <button class="btn ${state.activeView === 'users' ? 'btn-primary' : ''}" style="width: 100%; justify-content: flex-start;" onclick="switchView('users')">
        <i class="fas fa-users-cog"></i> Users
      </button>
      <div style="border-top: 1px solid var(--surface-border); margin: 1rem 0; padding-top: 1rem;">
        <button class="btn" style="width: 100%; justify-content: flex-start; color: var(--warning);" onclick="clearTodayLogs()">
          <i class="fas fa-trash-alt"></i> Reset Today
        </button>
      </div>
      <button class="btn" style="width: 100%; justify-content: flex-start; margin-top: auto; color: var(--error);" onclick="logout()">
        <i class="fas fa-sign-out-alt"></i> Logout
      </button>
    </div>
  `;
}

function renderDashboard() {
  const successLogs = state.logs.filter(l => l.status_pengawas === 'ACC' && l.status_security === 'ACC').length;
  const pendingLogs = state.logs.filter(l => l.status_security === 'PENDING').length;

  return `
    <div class="fade-in">
      <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 1.5rem; margin-bottom: 2rem;">
        <div class="glass" style="padding: 1.5rem;">
          <div style="color: var(--secondary); font-size: 0.875rem;">Total Scan Hari Ini</div>
          <div style="font-size: 2rem; font-weight: 700; margin-top: 0.5rem;">${state.logs.length}</div>
        </div>
        <div class="glass" style="padding: 1.5rem;">
          <div style="color: var(--success); font-size: 0.875rem;">Berhasil Verifikasi</div>
          <div style="font-size: 2rem; font-weight: 700; margin-top: 0.5rem;">${successLogs}</div>
        </div>
        <div class="glass" style="padding: 1.5rem;">
          <div style="color: var(--warning); font-size: 0.875rem;">Menunggu Security</div>
          <div style="font-size: 2rem; font-weight: 700; margin-top: 0.5rem;">${pendingLogs}</div>
        </div>
      </div>

      <div class="glass" style="padding: 1.5rem;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
          <h2>Log Scan Real-time</h2>
          <button class="btn" onclick="fetchLogs()" style="padding: 0.5rem 1rem;">
            <i class="fas fa-sync-alt"></i> Refresh
          </button>
        </div>
        <div class="table-container">
          <table>
            <thead>
              <tr>
                <th>ID Karyawan / Nama</th>
                <th>Status Pengawas</th>
                <th>Status Security</th>
                <th>Scan Pengawas At</th>
                <th>Scan Security At</th>
              </tr>
            </thead>
            <tbody>
              ${state.logs.map(log => `
                <tr>
                  <td style="font-weight: 600;">${log.id_karyawan}</td>
                  <td>
                    <span class="badge ${log.status_pengawas === 'ACC' ? 'badge-success' : 'badge-warning'}">
                      ${log.status_pengawas}
                    </span>
                  </td>
                  <td>
                    <span class="badge ${log.status_security === 'ACC' ? 'badge-success' : 'badge-warning'}">
                      ${log.status_security}
                    </span>
                  </td>
                  <td style="color: var(--secondary); font-size: 0.75rem;">${log.pengawas_scanned_at || '-'}</td>
                  <td style="color: var(--secondary); font-size: 0.75rem;">${log.security_scanned_at || '-'}</td>
                </tr>
              `).join('')}
              ${state.logs.length === 0 ? '<tr><td colspan="5" style="text-align: center; padding: 3rem; color: var(--secondary);">Belum ada data hari ini</td></tr>' : ''}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  `;
}

function renderHistory() {
  return `
    <div class="fade-in">
      <div class="glass" style="padding: 1.5rem; margin-bottom: 2rem;">
        <div style="display: flex; gap: 1rem; align-items: flex-end; flex-wrap: wrap;">
          <div class="input-group" style="margin-bottom: 0; flex: 1; min-width: 200px;">
            <label>Pilih Tanggal History</label>
            <select id="history-date-select" style="width: 100%; padding: 0.75rem; background: rgba(15, 23, 42, 0.5); border: 1px solid var(--surface-border); border-radius: 8px; color: white;">
              <option value="">Pilih Tanggal...</option>
              ${state.historyDates.map(date => `<option value="${date}">${date}</option>`).join('')}
            </select>
          </div>
          <button class="btn btn-primary" onclick="loadHistory()">
            <i class="fas fa-search"></i> LIHAT LOG
          </button>
        </div>
      </div>

      <div class="glass" style="padding: 1.5rem;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem;">
          <h2>Log History ${state.selectedHistoryDate || ''}</h2>
        </div>
        <div class="table-container">
          <table>
            <thead>
              <tr>
                <th>ID Karyawan / Nama</th>
                <th>Status Pengawas</th>
                <th>Status Security</th>
                <th>Scan Pengawas At</th>
                <th>Scan Security At</th>
              </tr>
            </thead>
            <tbody>
              ${state.historyLogs?.map(log => `
                <tr>
                  <td style="font-weight: 600;">${log.id_karyawan}</td>
                  <td><span class="badge badge-success">${log.status_pengawas}</span></td>
                  <td><span class="badge badge-success">${log.status_security}</span></td>
                  <td style="color: var(--secondary); font-size: 0.75rem;">${log.pengawas_scanned_at || '-'}</td>
                  <td style="color: var(--secondary); font-size: 0.75rem;">${log.security_scanned_at || '-'}</td>
                </tr>
              `).join('') || '<tr><td colspan="5" style="text-align: center; padding: 3rem; color: var(--secondary);">Pilih tanggal untuk melihat history</td></tr>'}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  `;
}

function renderUsers() {
  return `
    <div class="fade-in">
      <div class="glass" style="padding: 1.5rem; margin-bottom: 2rem;">
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <h2>User Management</h2>
          <button class="btn btn-primary" onclick="showAddUserModal()">
            <i class="fas fa-plus"></i> TAMBAH USER
          </button>
        </div>
      </div>

      <div class="glass" style="padding: 1.5rem;">
        <div class="table-container">
          <table>
            <thead>
              <tr>
                <th>Username</th>
                <th>Role</th>
                <th>Created At</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              ${state.users.map(user => `
                <tr>
                  <td style="font-weight: 600;">${user.username}</td>
                  <td><span class="badge badge-success">${user.role}</span></td>
                  <td style="color: var(--secondary); font-size: 0.75rem;">${user.created_at}</td>
                  <td>
                    <button class="btn" style="color: var(--error); padding: 0.25rem 0.5rem;" onclick="deleteUser(${user.id})">
                      <i class="fas fa-trash"></i>
                    </button>
                  </td>
                </tr>
              `).join('')}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  `;
}

function renderApp() {
  const app = document.querySelector('#app');
  if (!state.isLoggedIn) {
    renderLogin();
    return;
  }

  app.innerHTML = `
    <div style="display: grid; grid-template-columns: 280px 1fr; gap: 2rem; min-height: calc(100vh - 4rem);">
      <aside>${renderSidebar()}</aside>
      <main id="main-content">
        ${state.activeView === 'dashboard' ? renderDashboard() :
      state.activeView === 'history' ? renderHistory() :
        state.activeView === 'users' ? renderUsers() : 'View not implemented'}
      </main>
    </div>
  `;
}

// --- Controller Logic ---

window.switchView = async (view) => {
  state.activeView = view;
  if (view === 'dashboard') fetchLogs();
  if (view === 'history') {
    const data = await apiCall('/dates-history');
    state.historyDates = data.dates;
  }
  if (view === 'users') {
    const data = await apiCall('/admin/users');
    state.users = data.users;
  }
  renderApp();
};

window.loadHistory = async () => {
  const date = document.querySelector('#history-date-select').value;
  if (!date) return;
  state.selectedHistoryDate = date;
  const data = await apiCall(`/logs-history/${date}`);
  state.historyLogs = data.logs;
  renderApp();
};

window.logout = () => {
  state.isLoggedIn = false;
  state.user = null;
  renderApp();
};

window.fetchLogs = async () => {
  try {
    const data = await apiCall('/logs');
    state.logs = data.logs;
    renderApp();
  } catch (err) {
    console.error('Fetch logs failed', err);
  }
};

window.deleteUser = async (id) => {
  if (!confirm('Hapus user ini?')) return;
  try {
    await apiCall(`/admin/users/${id}`, { method: 'DELETE' });
    state.users = state.users.filter(u => u.id !== id);
    renderApp();
  } catch (err) {
    alert(err.message);
  }
};

window.showAddUserModal = () => {
  const username = prompt('Masukkan Username baru:');
  if (!username) return;
  const password = prompt('Masukkan Password:');
  if (!password) return;
  const role = prompt('Masukkan Role (pengawas/security):', 'pengawas');
  if (role !== 'pengawas' && role !== 'security') {
    alert('Role tidak valid');
    return;
  }

  apiCall('/admin/users', {
    method: 'POST',
    body: JSON.stringify({ username, password, role }),
  }).then(user => {
    state.users.push(user);
    renderApp();
  }).catch(err => alert(err.message));
};

window.clearTodayLogs = async () => {
  if (!confirm('Hapus semua log hari ini? (Data history akan tetap tersimpan)')) return;
  try {
    const res = await apiCall('/daily-reset', { method: 'POST' });
    alert(res.message);
    fetchLogs();
  } catch (err) {
    alert(err.message);
  }
};

// Start
renderApp();
if (state.isLoggedIn) fetchLogs();
