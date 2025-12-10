import ethers from "ethers";
import dotenv from "dotenv";

dotenv.config();

async function main() {

    const rpcUrl = process.env.ZKSYNC_RPC_URL;
    console.log(`Using RPC URL: ${rpcUrl}`);
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);

    const latestBatch = await provider.send("zks_L1BatchNumber", []);
    console.log(`Latest batch: ${latestBatch}`);

    const storageKeys = ["0x4d2f31e8578316b1eee225feb6442c49f42083864fa317ea81928e275ad2e366"];
        // "0x8af18107777760cbe302f71d4b1f34b4938de74d5846a5f397fde3446e33ec3a",
        // "0xc34095206a7e18c8ac745c8619f36b572ad998b82cb44029b9f154bb52e6baca",
        // "0x5651a358ee5a251ce5ae208d34a656d42ea2b2d2fc39c99585031a315c9e3bed",
        // "0xedfba15a198418927ad5a6d01a40199b2ba5a6641fcdb830c8633b26a0f56c12",
        // "0x4dcd3694b48be20029231dcd8c9cafa2918b74fbfc27d091c7e4f302f4f40e5e",
        // "0x3602bb54759588254273899f6b644c3bcc237268527ea064248f6739464e9a7a",
        // "0x8f21b220b7a2434e905f55add2c91f0a4f8ac76ed78c5f497602430818c554b9",
        // "0x12cbfcf823575cdf5670361f33bea5ab5074cbf2a4161dd8b6f256abd9865f71",
        // "0x3cd29f2eae832264383c0d36cdace1c6f7f2fdc0986fc7f4a9e03f63947a9067",
        // "0x56c56aa1c6fbba4c06a1f59e900474c03865323cd4214f485bb612362f43a6bd",
        // "0x3d327832337ddafb36270d814d21100c49d258afea7e651d1762fcdf44704356",
        // "0x5f563e5f1a5bbacddfcbd1f92f6254c4ed4a4e1c3f6072ed4a339cc702e849d7",
        // "0xb05359a447c3932f484596cadcb51ae96d7982fa6a4b6f5eaff69288d76dc439",
        // "0x37a12b6176c62876b5518cef46bc84469d06c3440dc14b215107fefbb86616c3",
        // "0x01ca2e9b062fcfbb33e759050a358be457bb1e921d4241813ee2d8ba80706123",
        // "0x95de301f0bdb83fdf9fd5493de4a38c75d3d6dfc665e5ed960ffa56634afcd1f",
        // "0xb60433819958ce96c7899aad995af89cd7c7fb2155c63939eee29a5ac8abc275",
        // "0xd2b9fdff34156cb0aedbf0aada02354e4651921695192daef84c4a9becff0d25",
        // "0x41a887db53f910b460886d06eb79ec516e03acb3ed8bb5f9fdf9d883d664bcd6",
        // "0xc80b0443c7bee5c8e31e3449dad0affcedfb75f4a8d310a66b2908b9fdb8cc88",
        // "0x88ae8315e8916d2311e923eb58087223dda8e686ad13fb1d7005e98ea982c310",
        // "0x4513cb503e66d3752673da206441ac555236486809e44c7a81369467d82d30d2",
        // "0x6d639e221808c9cb69aa5b19a8b3cc55b3e2701b4bff109aed9e5644cc64d323",
        // "0x42c0e6cfbd0f0bc0505538ec04c120a21477c109b0a576247d7d45919d400ede",
        // "0x9cb345b482f45358dd0a57afce927d7b85756f6d49c2ae0dc7f7908fb27d3cc2",
        // "0x0a39e3389d2437d160f3d95cdf30f61c1afd52a2f82cafd2ac32a6b6ea823e9b",
        // "0x9ebd7b37a21fb0c74d0040a941038887caf4e4c7dfaa182b82915cacc6191025",
        // "0x4550ab30af8c76557a74d051eb43a964889d383d6da343c6a4f4799595d86f9c"]


    const storageProof = await provider.send("zks_getProof", ["0x40F58Bd4616a6E76021F1481154DB829953BF01B", storageKeys, 0x48d0]);

    const batchDetails = await provider.send("zks_getL1BatchDetails", [0x48d0]);



    console.log(storageProof);

    console.log(storageProof.storageProof[0].proof);

    console.log(batchDetails);


    console.log("================================================");
    console.log("Gateway")

    const gatewayStorageKeys = ["0x8c679509bce200e0a72120fb84bd8cf10205459bda331dcf9162a17e3ec81dd3"];

    const newProvider = new ethers.providers.JsonRpcProvider("https://rpc.era-gateway-testnet.zksync.dev");

    const storageProofGateway = await newProvider.send("zks_getProof", ["0x939f73bFD6809a9650aDb2707e44cC0f8aB0874F", gatewayStorageKeys, 43863]);
    console.log(storageProofGateway);

    console.log(storageProofGateway.storageProof[0].proof);


    const l1BatchDetailsGateway = await newProvider.send("zks_getL1BatchDetails", [43863]);

    console.log(l1BatchDetailsGateway);


    
}

main();