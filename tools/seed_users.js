import { createClient } from '@supabase/supabase-js';
import * as fs from 'fs';
import * as path from 'path';

// Read web/.env or .env
let envContent = '';
try {
  envContent = fs.readFileSync(path.resolve('web/.env'), 'utf-8');
} catch {
  try {
    envContent = fs.readFileSync(path.resolve('.env.local'), 'utf-8');
  } catch {}
}

const getEnv = (key) => {
  const match = envContent.match(new RegExp(`^${key}=(.*)$`, 'm'));
  return match ? match[1].trim() : process.env[key];
};

const supabaseUrl = getEnv('VITE_SUPABASE_URL') || getEnv('SUPABASE_URL');
const serviceKey = getEnv('SUPABASE_SERVICE_ROLE_KEY') || process.argv[2];

if (!supabaseUrl) {
  console.error('Error: VITE_SUPABASE_URL not found in web/.env');
  process.exit(1);
}

if (!serviceKey) {
  console.log('\nUsage: node tools/seed_users.js <SUPABASE_SERVICE_ROLE_KEY>');
  console.log('You can find your service_role secret in Supabase Dashboard > Project Settings > API > service_role secret\n');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const demoUsers = [
  {
    email: 'student1@roompulse.local',
    password: 'password123',
    name: 'Alice Pratama',
    role: 'student',
  },
  {
    email: 'student2@roompulse.local',
    password: 'password123',
    name: 'Bob Santoso',
    role: 'student',
  },
  {
    email: 'staff@roompulse.local',
    password: 'password123',
    name: 'Library Staff Lead',
    role: 'staff',
  },
];

async function seed() {
  console.log(`[*] Connecting to Supabase at ${supabaseUrl}...`);

  for (const u of demoUsers) {
    console.log(`[*] Creating demo user: ${u.email}...`);

    // Check if user already exists
    const { data: listData } = await supabase.auth.admin.listUsers();
    const existing = listData?.users?.find((x) => x.email === u.email);

    let userId = existing?.id;

    if (existing) {
      console.log(`    User exists, updating password for ${u.email}...`);
      await supabase.auth.admin.updateUserById(existing.id, {
        password: u.password,
        email_confirm: true,
        user_metadata: { display_name: u.name },
      });
    } else {
      const { data, error } = await supabase.auth.admin.createUser({
        email: u.email,
        password: u.password,
        email_confirm: true,
        user_metadata: { display_name: u.name },
      });

      if (error) {
        console.error(`    Failed to create ${u.email}:`, error.message);
        continue;
      }
      userId = data.user.id;
      console.log(`    Created user ${u.email} (ID: ${userId})`);
    }

    // Ensure profile row exists
    if (userId) {
      await supabase.from('profiles').upsert({
        id: userId,
        display_name: u.name,
        role: u.role,
      });
      console.log(`    Profile linked for ${u.name} (${u.role})`);
    }
  }

  console.log('\n[SUCCESS] All 3 demo accounts created & confirmed! You can now log in.');
}

seed().catch(console.error);
