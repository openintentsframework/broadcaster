async function createConfig() {
  const { defineConfig } = await import('@wagmi/cli/config')
  const { hardhat } = await import('@wagmi/cli/plugins')

  return defineConfig({
    plugins: [
      hardhat({
        project: '.',
      }),
    ],
    out: 'wagmi/abi.ts',
  })
}

module.exports = createConfig
module.exports.default = createConfig
