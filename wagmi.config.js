import { defineConfig } from '@wagmi/cli'
import { hardhat } from '@wagmi/cli/plugins'

export default defineConfig({
  plugins: [
    hardhat({
      project: '.',
    }),
  ],
  out: 'wagmi/abi.ts',
})
