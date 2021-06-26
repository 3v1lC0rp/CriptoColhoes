//SPDX-License-Identifier: MIT
pragma solidity >0.6.0;
pragma experimental ABIEncoderV2;

// Imported OZ helper contracts
import "./token/ERC20/IERC20.sol";
import "./token/ERC20/utils/SafeERC20.sol";
import "./utils/Address.sol";
import "./Initializable.sol";

// Inherited allowing for ownership of contract
import "./access/Ownable.sol";

// Allows for time manipulation. Set to 0x address on test/mainnet deploy
import "./Testable.sol";

// Safe math 
import "./utils/math/SafeMath.sol";
import "./SafeMath16.sol";
import "./SafeMath8.sol";

// TODO rename to Lottery when done
contract Lottery is Ownable, Initializable, Testable {
    // Libraries 
    // Safe math
    using SafeMath for uint256;
    using SafeMath16 for uint16;
    using SafeMath8 for uint8;
    // Safe ERC20
    using SafeERC20 for IERC20;
    // Address functionality 
    using Address for address;

    // State variables 
    // Instance of Cake token (collateral currency for lotto)
    IERC20 internal cake_;

    // Request ID for random number
    bytes32 internal requestId_;
    // Counter for lottery IDs 
    uint256 private lotteryIdCounter_;

    // Lottery size
    uint8 public sizeOfLottery_;
    // Max range for numbers (starting at 0)
    uint16 public maxValidRange_;
    
    // Dev Mainantence fees 
    uint256 public devFee;
    
    // jackpot
    uint256 public pintelho;
    
     // number of devs
    uint256 public nDevs_;
    
    // devs addresses
    address[] public aDevs;
    
    //numebr of tickets sold
    uint256 internal totalSupply_;
     
     //max integer used to set allowance to spend tokens
     uint256 MAX_INT = 2**256 - 1;
     
    // Storage for ticket information
    struct TicketInfo {
        address owner;
        bool claimed;
        uint256 lotteryId;
    }
    
    // Token ID => Token information 
    mapping(uint256 => TicketInfo) internal ticketInfo_;
    
    // User address => Lottery ID => Ticket IDs
    mapping(address => mapping(uint256 => uint256[])) internal userTickets_;

    // Represents the status of the lottery
    enum Status { 
        NotStarted,     // The lottery has not started yet
        Open,           // The lottery is open for ticket purchases 
        Closed,         // The lottery is no longer open for ticket purchases
        Completed       // The lottery has been closed and the numbers drawn
    }
    
    // All the needed info around a lottery
    struct LottoInfo {
        uint256 lotteryID;          // ID for lotto
        Status lotteryStatus;       // Status for lotto
        uint256 prizePoolInCake;    // The amount of cake for prize money
        uint256 costPerTicket;      // Cost per ticket in $cake
        uint8[] prizeDistribution;  // The distribution for prize money
        uint256 startingTimestamp;      // Block timestamp for star of lotto
        uint256 closingTimestamp;       // Block timestamp for end of entries
        uint256[] winningTickets;     // The winning participants
    }
    // Lottery ID's to info
    mapping(uint256 => LottoInfo) internal allLotteries_;
    mapping(address => uint256) internal winnersPrize;

    //-------------------------------------------------------------------------
    // EVENTS
    //-------------------------------------------------------------------------

    event NewBatchMint(address indexed minter, uint256[] ticketIDs, uint256 totalCost);

    event RequestNumbers(uint256 lotteryId, bytes32 requestId);

    event UpdatedSizeOfLottery(address admin, uint8 newLotterySize);

    event UpdatedMaxRange(address admin, uint16 newMaxRange);

    event LotteryOpen(uint256 lotteryId, uint256 ticketSupply);

    event LotteryClose(uint256 lotteryId, uint256 ticketSupply);
    
    event AddDev(address admin, address newDev);

    event InfoBatchMint(
        address indexed receiving, 
        uint256 lotteryId,
        uint256 amountOfTokens, 
        uint256[] tokenIds
    );

    //-------------------------------------------------------------------------
    // MODIFIERS
    //-------------------------------------------------------------------------

     modifier notContract() {
        require(!address(msg.sender).isContract(), "contract not allowed");
        require(msg.sender == tx.origin, "proxy contract not allowed");
       _;
    }

    //-------------------------------------------------------------------------
    // CONSTRUCTOR
    //-------------------------------------------------------------------------

    constructor(address _cake, address _timer
    ) Testable(_timer){

        require(_cake != address(0),"Contracts cannot be 0 address");

        cake_ = IERC20(_cake);
        sizeOfLottery_ = 3;

        nDevs_ = 5;
        aDevs.push(0xDc9111DB04cE2Db377A3cFAB7E6867Da17164e1c);
        aDevs.push(0xfb5ec89Ee8A00Bcb39E07aa70d3eC060de0f6865);
        aDevs.push(0x72f9Be350D3fD6F9Eba6fBFf8EDd82AC90Ec1105);
        aDevs.push(0xE044559A94ae51D376e42F9eF8d93772044Fc3c4);
        aDevs.push(0x957f996D64fD4aB8dC07140aE0fc1ebA281a7808);
        
        
    }

    //-------------------------------------------------------------------------
    // VIEW FUNCTIONS
    //-------------------------------------------------------------------------

    function costToBuyTickets(uint256 _lotteryId, uint256 _numberOfTickets) external view returns(uint256 totalCost) {
        uint256 pricePer = allLotteries_[_lotteryId].costPerTicket;
        totalCost = pricePer.mul(_numberOfTickets);
        return totalCost;
    }


    function getBasicLottoInfo(uint256 _lotteryId) external view returns(LottoInfo memory)
    {
        return(allLotteries_[_lotteryId]); 
    }

    //-------------------------------------------------------------------------
    // VIEW FUNCTIONS
    //-------------------------------------------------------------------------

    function getTotalSupply() public view returns(uint256) {
        return totalSupply_;
    }
    
    function getPrize(address dev) public view returns(uint256) {
        return winnersPrize[dev];
    }

    /**
     * @param   _ticketID: The unique ID of the ticket
     * @return  address: Owner of ticket
     */
    function getOwnerOfTicket(
        uint256 _ticketID
    ) 
        public
        view 
        returns(address) 
    {
        return ticketInfo_[_ticketID].owner;
    }

    function getTicketClaimStatus(
        uint256 _ticketID
    ) 
        external 
        view
        returns(bool) 
    {
        return ticketInfo_[_ticketID].claimed;
    }
    
     function getDevFee() 
        external 
        view
        returns(uint256) 
    {
        return devFee;
    }

    function getUserTickets(
        uint256 _lotteryId,
        address _user
    ) 
        external 
        view 
        returns(uint256[] memory) 
    {
        return userTickets_[_user][_lotteryId];
    }

    //-------------------------------------------------------------------------
    // STATE MODIFYING FUNCTIONS 
    //-------------------------------------------------------------------------

    //-------------------------------------------------------------------------
    // Restricted Access Functions (onlyOwner)

    function updateSizeOfLottery(uint8 _newSize) external onlyOwner() {
        require(
            sizeOfLottery_ != _newSize,
            "Cannot set to current size"
        );
        require(
            sizeOfLottery_ != 0,
            "Lottery size cannot be 0"
        );
        sizeOfLottery_ = _newSize;

        emit UpdatedSizeOfLottery(msg.sender, _newSize);
    }
        
    //Dev fee
    function addDev(address dev) external onlyOwner() {
        nDevs_ = nDevs_.add(1);
        aDevs.push(dev);
        
        emit AddDev(msg.sender, dev);
    }


    function drawWinningNumbers(
        uint256 _lotteryId, 
        uint256 _seed
    ) 
        external 
        onlyOwner() 
    {
        // Checks that the lottery is past the closing block
        require(
            allLotteries_[_lotteryId].closingTimestamp <= getCurrentTime(),
            "Cannot set winning numbers during lottery"
        );
        // Checks lottery numbers have not already been drawn
        require(
            allLotteries_[_lotteryId].lotteryStatus == Status.Open,
            "Lottery State incorrect for draw"
        );
        // Sets lottery status to closed
        allLotteries_[_lotteryId].lotteryStatus = Status.Closed;
        // Requests a random number from the generator
        //requestId_ = bytes32(_seed);
        // Emits that random number has been requested
        emit RequestNumbers(_lotteryId, requestId_);
        

        allLotteries_[_lotteryId].lotteryStatus = Status.Completed;
        allLotteries_[_lotteryId].winningTickets = _split(_seed, allLotteries_[_lotteryId].prizePoolInCake, allLotteries_[_lotteryId].costPerTicket, allLotteries_[_lotteryId].prizeDistribution);
         // Removing the prize amount from the pool
        allLotteries_[_lotteryId].prizePoolInCake = 0;

        emit LotteryClose(_lotteryId, getTotalSupply());
    }
    
    
    /**
     * @param   _to The address being minted to
     * @param   _numberOfTickets The number of NFT's to mint
     * @notice  Only the lotto contract is able to mint tokens. 
        // uint8[][] calldata _lottoNumbers
     */
    function batchMint(
        address _to,
        uint256 _lotteryId,
        uint8 _numberOfTickets
    )
        internal 
        returns(uint256[] memory)
    {
        // Storage for the amount of tokens to mint (always 1)
        uint256[] memory amounts = new uint256[](_numberOfTickets);
        
        // Storage for the token IDs
        uint256[] memory tokenIds = new uint256[](_numberOfTickets);
        
        for (uint8 i = 0; i < _numberOfTickets; i++) {
            // Incrementing the tokenId counter
            totalSupply_ = totalSupply_.add(1);
            tokenIds[i] = totalSupply_;
            amounts[i] = 1;

            // Storing the ticket information 
            ticketInfo_[totalSupply_] = TicketInfo(_to, false, _lotteryId);
            userTickets_[_to][_lotteryId].push(totalSupply_);
        }

        // Emitting relevant info
        emit InfoBatchMint(  _to, _lotteryId,  _numberOfTickets, tokenIds);
        
        // Returns the token IDs of minted tokens
        return tokenIds;
    }


    /**
     * @param   _prizeDistribution An array defining the distribution of the 
     *          prize pool. I.e if a lotto has 5 numbers, the distribution could
     *          be [5, 10, 15, 20, 30] = 95%. This means if you get one number
     *          right you get 5% of the pool, 2 matching would be 10% and so on.
     * @param   _startingTimestamp The block timestamp for the beginning of the 
     *          lottery. 
     * @param   _closingTimestamp The block timestamp after which no more tickets
     *          will be sold for the lottery. Note that this timestamp MUST
     *          be after the starting block timestamp. 
     */
    function createNewLotto(
        uint8[] calldata _prizeDistribution,
        uint256 _costPerTicket,
        uint256 _startingTimestamp,
        uint256 _closingTimestamp
    ) 
        external
        onlyOwner()
        returns(uint256 lotteryId)
    {
        require(
            _prizeDistribution.length == sizeOfLottery_,
            "Invalid distribution"
        );
        uint256 prizeDistributionTotal = 0;
        for (uint256 j = 0; j < _prizeDistribution.length; j++) {
            prizeDistributionTotal = prizeDistributionTotal.add(
                uint256(_prizeDistribution[j])
            );
        }
        // Ensuring that prize distribution total is 95% (1% dev fee, 4% jackpot)
        require(
            prizeDistributionTotal == 95,
            "Prize distribution is not 95%"
        );
        // Ensure price per ticket is not 0
        require( _costPerTicket != 0, "Prize or cost cannot be 0");
        
        require(_startingTimestamp != 0 && _startingTimestamp < _closingTimestamp, "Timestamps for lottery invalid");
        
        // Incrementing lottery ID 
        lotteryIdCounter_ = lotteryIdCounter_.add(1);
        
        lotteryId = lotteryIdCounter_;
        
        uint256[] memory winningNumbers = new uint256[](sizeOfLottery_);
        
        Status lotteryStatus;
        
        if(_startingTimestamp >= getCurrentTime()) {
            lotteryStatus = Status.Open;
        } else {
            lotteryStatus = Status.NotStarted;
        }
        
        // Saving data in struct
        LottoInfo memory newLottery = LottoInfo(
            lotteryId,
            lotteryStatus,
            0,
            _costPerTicket,
            _prizeDistribution,
            _startingTimestamp,
            _closingTimestamp,
            winningNumbers
        );
        allLotteries_[lotteryId] = newLottery;

        // Emitting important information around new lottery.
        emit LotteryOpen(lotteryId, getTotalSupply());
    }

    
    
     //Dev fee distribution
    function devCalc() internal onlyOwner() {
        
        uint256 tempFees = devFee;
        
        devFee = 0;
        
        for(uint i = 0; i < nDevs_; i++){

            address currentDev = aDevs[i];
            
            winnersPrize[currentDev] = winnersPrize[currentDev].add(tempFees.div(5));
        }
    }

    //-------------------------------------------------------------------------
    // General Access Functions

    function batchBuyLottoTicket(uint256 _lotteryId, uint8 _numberOfTickets) external  notContract(){
        // Ensuring the lottery is within a valid time
        require(
            getCurrentTime() >= allLotteries_[_lotteryId].startingTimestamp,
            "Invalid time for mint:start"
        );
        require(
            getCurrentTime() < allLotteries_[_lotteryId].closingTimestamp,
            "Invalid time for mint:end"
        );
        if(allLotteries_[_lotteryId].lotteryStatus == Status.NotStarted) {
            if(allLotteries_[_lotteryId].startingTimestamp <= getCurrentTime()) {
                allLotteries_[_lotteryId].lotteryStatus = Status.Open;
            }
        }
        require(
            allLotteries_[_lotteryId].lotteryStatus == Status.Open,
            "Lottery not in state for mint"
        );
        require(
            _numberOfTickets <= 50,
            "Batch mint too large"
        );


        // Getting the cost and discount for the token purchase
        uint256 totalCost  = this.costToBuyTickets(_lotteryId, _numberOfTickets);
        
        //calculate the 1% dev fee
        devFee = devFee.add(totalCost.div(100));
        
        allLotteries_[_lotteryId].prizePoolInCake = allLotteries_[_lotteryId].prizePoolInCake.add(totalCost); 
        
        cake_.transferFrom(msg.sender, address(this), totalCost);
        
        //Batch mints the user their tickets
        uint256[] memory ticketIds = batchMint(msg.sender, _lotteryId,  _numberOfTickets);
        
        // Emitting event with all information
        emit NewBatchMint(msg.sender, ticketIds, totalCost);
    }

    function claimReward() external notContract() {
        
        require(winnersPrize[msg.sender] > 0, "You were not a winner or already claimed your prize");
        
        // Getting the prize amount for those matching tickets
        uint256 prizeAmount = winnersPrize[msg.sender];
       
        winnersPrize[msg.sender] = 0;
       
        // Transfering the user their winnings
        cake_.safeTransfer(address(msg.sender), prizeAmount);
    }



    //-------------------------------------------------------------------------
    // INTERNAL FUNCTIONS 
    //-------------------------------------------------------------------------

    function _split(uint256 _randomNumber, uint256 prize, uint costTicket, uint8[] memory shares) internal returns(uint16[] memory) 
    {
        // Temparary storage for winning numbers
        uint16[] memory winningNumbers = new uint16[](sizeOfLottery_);
        
        
        //get number of players pf this lottery
        uint256 numberOfPlayers = prize.div(costTicket);
        
        // add block time and difficulty to the random number to make it more random
        uint256 tempRand = _randomNumber.add(block.timestamp).add(block.difficulty);
        
        // Loops the size of the number of tickets in the lottery
        for(uint i = 0; i < sizeOfLottery_; i++){
            // Encodes the pseudo random number with its position in loop
            bytes32 hashOfRandom = keccak256(abi.encodePacked(tempRand, i));
            // Casts random number hash into uint256
            uint256 numberRepresentation = uint256(hashOfRandom);
            
            // Sets the winning number position to a uint16 of random hash number
            winningNumbers[i] = uint16(totalSupply_.sub(numberRepresentation.mod(numberOfPlayers)));
            
            address currentWinner = getOwnerOfTicket(winningNumbers[i]);
            
            uint256 gains = prize.mul(shares[i]).div(100);
            
            winnersPrize[currentWinner] = winnersPrize[currentWinner].add(gains);
        }
        
        // Encodes the pseudo random number 
            bytes32 hashOfRand = keccak256(abi.encodePacked(tempRand, block.timestamp));
        // Casts random number hash into uint256
            uint256 numberOfRandom = uint256(hashOfRand);
        
        if(uint16(numberOfRandom.mod(20)) != 1){
             pintelho = pintelho.add(prize.mul(4).div(100));
        }else{
            // Casts random number hash into uint256
            address pintelho_winner = getOwnerOfTicket(uint16(numberOfRandom.mod(numberOfPlayers)));
            
            uint256 temp_pintelho = pintelho;
            pintelho.sub(temp_pintelho);
            winnersPrize[pintelho_winner] = winnersPrize[pintelho_winner].add(temp_pintelho);
        }
        
        devCalc();
        
    return winningNumbers;
    }
    
    
    /**
     * Claim ticket
     * @param   _ticketID The number ID of the ticket we want to claim
     * @param   _lotteryId The lotteryId 
     
    function claimTicket(uint256 _ticketID, uint256 _lotteryId) internal returns(bool) {
        require(
            ticketInfo_[_ticketID].claimed == false,
            "Ticket already claimed"
        );
        require(
            ticketInfo_[_ticketID].lotteryId == _lotteryId,
            "Ticket not for this lottery"
        );

        ticketInfo_[_ticketID].claimed = true;
        return true;
    }*/

}
