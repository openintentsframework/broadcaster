async function createConfig() {
  const { defineConfig } = await import('@wagmi/cli')
  const { hardhat } = await import('@wagmi/cli/plugins')

  // For now, generate ABIs for arbitrum provers only
  // To add support for other chains in the future:
  // 1. Add them to the exclude list below OR
  // 2. Create chain-specific ABI exports (see nameResolver pattern commented out)
  
  return defineConfig({
    plugins: [
      hardhat({
        project: '.',
        exclude: [
          '**/*.t.sol',
          '**/*.s.sol',
          '**/test/**',
          // Exclude other chains' provers to avoid duplicates
          // Add new chains here as needed
          '**/provers/optimism/**',
          // '**/provers/polygon/**',
          // '**/provers/base/**',
        ],
        // Optional: Use nameResolver to add chain prefixes
        // nameResolver: (contract) => {
        //   const match = contract.sourceName.match(/provers\/(\w+)\//)
        //   if (match) {
        //     const chain = match[1]
        //     const prefix = chain.charAt(0).toUpperCase() + chain.slice(1)
        //     return `${prefix}${contract.name}`
        //   }
        //   return contract.name
        // },
      }),
    ],
    out: 'wagmi/abi.ts',
  })
}

module.exports = createConfig
module.exports.default = createConfig
