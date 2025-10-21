import dotenv from 'dotenv'
dotenv.config()
import type { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox-viem'

const config: HardhatUserConfig = {
  solidity: '0.8.28',
  paths: {
    sources: './src',
  },
};

export default config
