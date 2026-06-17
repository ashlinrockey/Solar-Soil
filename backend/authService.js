import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcryptjs';
import low from 'lowdb';
import FileSync from 'lowdb/adapters/FileSync.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Use a JSON file as the database — stored next to server.js
const adapter = new FileSync(join(__dirname, 'users.db.json'));
const db = low(adapter);

// Set default structure
db.defaults({ users: [] }).write();

/**
 * Seed the default admin user if the DB is empty.
 * username: "username" / password: "password"
 */
const seedDefaultUser = async () => {
  const existing = db.get('users').find({ username: 'username' }).value();
  if (!existing) {
    const hashedPassword = await bcrypt.hash('password', 10);
    db.get('users').push({
      id: 1,
      username: 'username',
      password: hashedPassword,
      role: 'admin',
      createdAt: new Date().toISOString(),
    }).write();
    console.log('[Auth] Default user seeded: username / password');
  } else {
    console.log('[Auth] Default user already exists in database.');
  }
};

/**
 * Find a user by username and validate their password.
 * @param {string} username
 * @param {string} plainPassword
 * @returns {{ success: boolean, user?: object, message: string }}
 */
export const authenticateUser = async (username, plainPassword) => {
  const user = db.get('users').find({ username }).value();

  if (!user) {
    return { success: false, message: 'Invalid username or password.' };
  }

  const isMatch = await bcrypt.compare(plainPassword, user.password);

  if (!isMatch) {
    return { success: false, message: 'Invalid username or password.' };
  }

  // Return user info without the password hash
  const { password, ...safeUser } = user;
  return { success: true, user: safeUser, message: 'Login successful.' };
};

/**
 * Change a user's password (requires current password verification).
 * @param {string} username
 * @param {string} oldPassword
 * @param {string} newPassword
 * @returns {{ success: boolean, message: string }}
 */
export const changePassword = async (username, oldPassword, newPassword) => {
  const user = db.get('users').find({ username }).value();
  if (!user) {
    return { success: false, message: 'User not found.' };
  }
  const isMatch = await bcrypt.compare(oldPassword, user.password);
  if (!isMatch) {
    return { success: false, message: 'Current password is incorrect.' };
  }
  const hashed = await bcrypt.hash(newPassword, 10);
  db.get('users').find({ username }).assign({ password: hashed }).write();
  return { success: true, message: 'Password updated successfully.' };
};

/**
 * Get all users (without passwords) — for admin use.
 */
export const getAllUsers = () => {
  return db.get('users').value().map(({ password, ...u }) => u);
};

// Seed default user on module load
await seedDefaultUser();
