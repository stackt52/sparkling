import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Default output is fine for Firebase App Hosting (no `standalone` needed).
  agentRules: false,
  images: { unoptimized: true },
};

export default nextConfig;
