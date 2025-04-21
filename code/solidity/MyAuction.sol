// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract MyAuction is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC721HolderUpgradeable,
    UUPSUpgradeable
{
    event Registration(
        address indexed nftCA,
        uint256 indexed tokenId,
        address indexed from,
        uint256 auctionIdx,
        uint256 price
    );
    event Cancellation(
        address indexed nftCA,
        uint256 indexed tokenId,
        address indexed from,
        uint256 auctionIdx
    );
    event Bid(
        address indexed from,
        uint256 auctionIdx,
        uint256 bidIdx,
        uint256 price,
        uint256 expireAt
    );
    event BidCancellation(
        address indexed from,
        uint256 auctionIdx,
        uint256 bidIdx
    );
    event WithdrawNft(
        address indexed nftCA,
        uint256 indexed tokenId,
        address indexed from,
        uint256 auctionIdx,
        uint256 bidIdx,
        uint256 price,
        address nftSeller
    );
    event WithdrawToken(
        address indexed nftCA,
        uint256 indexed tokenId,
        address indexed from,
        uint256 auctionIdx,
        uint256 bidIdx,
        uint256 price,
        address nftOwner
    );

    bytes4 private constant _ERC721_INTERFACE_ID = 0x80ac58cd;
    IERC20 private tokenCA;

    struct Deal {
        uint256 fee;
        uint256 biddingMinutes;
        address feeRecipient;
    }
    mapping(address => Deal) public Deals;

    uint256 public auctionIdx;

    struct Bidding {
        uint256 price;
        address bidder;
        bool withdraw;
    }
    struct Auction {
        uint256 tokenId;
        uint256 startingBid;
        uint256 highestBid;
        uint256 bidIdx;
        uint256 endTime;
        mapping(uint256 => Bidding) biddings;
        address nftCA;
        address owner;
        bool complete;
    }
    mapping(uint256 => Auction) public Auctions;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 _tokenCA) public initializer {
        tokenCA = _tokenCA;
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ERC721Holder_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function addDeal(
        address _nftCA,
        uint256 _fee,
        address _feeRecipient
    ) public onlyOwner {
        IERC165 erc165 = IERC165(_nftCA);
        require(
            erc165.supportsInterface(_ERC721_INTERFACE_ID),
            "Unsupported contract"
        );

        require(_fee < 1000, "Invalid fee value");
        require(_feeRecipient != address(0), "Invalid fee recipient address");

        Deal storage deal = Deals[_nftCA];
        require(
            deal.feeRecipient == address(0),
            "The transaction already exists"
        );

        deal.fee = _fee;
        deal.feeRecipient = _feeRecipient;
        deal.biddingMinutes = 180;
    }

    function setFee(address _nftCA, uint256 _fee) public onlyOwner {
        Deal storage deal = Deals[_nftCA];
        require(deal.feeRecipient != address(0), "No such deal");
        require(_fee < 1000, "Invalid fee value");
        deal.fee = _fee;
    }
    function setFees(
        address[] calldata _nftCA,
        uint256[] calldata _fee
    ) external onlyOwner {
        require(
            _nftCA.length == _fee.length,
            "The size of the nftCA array does not match the size of the value array"
        );
        for (uint256 i; i < _nftCA.length; ) {
            setFee(_nftCA[i], _fee[i]);
            unchecked {
                i++;
            }
        }
    }

    function setFeeOwner(
        address _nftCA,
        address _feeRecipient
    ) public onlyOwner {
        Deal storage deal = Deals[_nftCA];
        require(deal.feeRecipient != address(0), "No such deal");
        require(_feeRecipient != address(0), "Invalid fee owner address");
        deal.feeRecipient = _feeRecipient;
    }
    function setFeeOwners(
        address[] calldata _nftCA,
        address[] calldata _feeRecipient
    ) external onlyOwner {
        require(
            _nftCA.length == _feeRecipient.length,
            "The size of the nftCA array does not match the size of the value array"
        );
        for (uint256 i; i < _nftCA.length; ) {
            setFeeOwner(_nftCA[i], _feeRecipient[i]);
            unchecked {
                i++;
            }
        }
    }

    function setBiddingMinutes(
        address _nftCA,
        uint256 _minutes
    ) public onlyOwner {
        Deal storage deal = Deals[_nftCA];
        require(deal.feeRecipient != address(0), "No such deal");
        require(_minutes > 0, "Invalid time value");
        deal.biddingMinutes = _minutes;
    }
    function setBiddingMinutesMulti(
        address[] calldata _nftCA,
        uint256[] calldata _minutes
    ) external onlyOwner {
        require(
            _nftCA.length == _minutes.length,
            "The size of the nftCA array does not match the size of the value array"
        );
        for (uint256 i; i < _nftCA.length; ) {
            setBiddingMinutes(_nftCA[i], _minutes[i]);
            unchecked {
                i++;
            }
        }
    }

    function registration(
        address _nftCA,
        uint256 _tokenId,
        uint256 _price
    ) public whenNotPaused {
        require(Deals[_nftCA].feeRecipient != address(0), "No such deal");
        require(_price >= 1 ether, "Starting bid must greater than 1 ether");
        require(
            _price <= 100000000 ether,
            "The starting bid must be less than or equal to 100000000 ether"
        );

        IERC721(_nftCA).safeTransferFrom(msg.sender, address(this), _tokenId);

        auctionIdx++;
        Auction storage auction = Auctions[auctionIdx];
        auction.nftCA = _nftCA;
        auction.tokenId = _tokenId;
        auction.owner = msg.sender;
        auction.startingBid = _price;

        emit Registration(_nftCA, _tokenId, msg.sender, auctionIdx, _price);
    }

    modifier isExistAuction(uint256 _auctionIdx) {
        require(Auctions[_auctionIdx].owner != address(0), "No such auction");
        _;
    }

    function cancellation(
        uint256 _auctionIdx
    ) public whenNotPaused isExistAuction(_auctionIdx) {
        Auction storage auction = Auctions[_auctionIdx];

        require(auction.owner == msg.sender, "Not an auction registrant");
        require(auction.complete == false, "Auction already closed");
        require(auction.bidIdx == 0, "Bidding has started");

        auction.complete = true;
        IERC721(auction.nftCA).safeTransferFrom(
            address(this),
            msg.sender,
            auction.tokenId
        );

        emit Cancellation(
            auction.nftCA,
            auction.tokenId,
            msg.sender,
            _auctionIdx
        );
    }

    function bid(
        uint256 _auctionIdx,
        uint256 _price
    ) public whenNotPaused isExistAuction(_auctionIdx) {
        Auction storage auction = Auctions[_auctionIdx];

        Deal storage deal = Deals[auction.nftCA];
        require(deal.feeRecipient != address(0), "Not exist deal");
        require(auction.complete == false, "Auction already closed");

        if (auction.bidIdx > 0) {
            require(auction.endTime > block.timestamp, "Auction has ended");
            require(auction.highestBid < _price, "Lower than the highest bid");
        } else {
            require(
                auction.startingBid <= _price,
                "Lower than the starting bid"
            );
        }

        auction.highestBid = _price;
        auction.endTime = block.timestamp + (deal.biddingMinutes * 1 minutes);
        require(tokenCA.transferFrom(msg.sender, address(this), _price));
        auction.bidIdx++;
        Bidding storage bidding = auction.biddings[auction.bidIdx];
        bidding.bidder = msg.sender;
        bidding.price = _price;

        emit Bid(
            msg.sender,
            _auctionIdx,
            auction.bidIdx,
            _price,
            auction.endTime
        );
    }

    function bidCancellation(
        uint256 _auctionIdx,
        uint256 _bidIdx
    ) public whenNotPaused isExistAuction(_auctionIdx) {
        Auction storage auction = Auctions[_auctionIdx];
        Bidding storage bidding = auction.biddings[_bidIdx];

        require(bidding.bidder == msg.sender, "Not a bidder");
        require(bidding.withdraw == false, "Already refunded");
        require(auction.bidIdx > _bidIdx, "Highest price non-refundable");

        bidding.withdraw = true;
        require(tokenCA.transfer(msg.sender, bidding.price));

        emit BidCancellation(msg.sender, _auctionIdx, _bidIdx);
    }

    function withdrawNft(
        uint256 _auctionIdx
    ) public whenNotPaused isExistAuction(_auctionIdx) {
        Auction storage auction = Auctions[_auctionIdx];

        require(auction.endTime <= block.timestamp, "Auction is in progress");
        require(auction.bidIdx > 0, "There is no bid history");
        Bidding storage bidding = auction.biddings[auction.bidIdx];
        require(bidding.bidder == msg.sender, "Not a bidder");
        require(auction.complete == false, "Already settled");

        bidding.withdraw = true;
        auction.complete = true;
        Deal storage deal = Deals[auction.nftCA];
        uint256 auctionFee = (auction.highestBid * deal.fee) / 1000;
        require(tokenCA.transfer(deal.feeRecipient, auctionFee));
        require(
            tokenCA.transfer(auction.owner, auction.highestBid - auctionFee)
        );
        IERC721(auction.nftCA).safeTransferFrom(
            address(this),
            msg.sender,
            auction.tokenId
        );

        emit WithdrawNft(
            auction.nftCA,
            auction.tokenId,
            msg.sender,
            _auctionIdx,
            auction.bidIdx,
            auction.highestBid,
            auction.owner
        );
    }

    function withdrawToken(
        uint256 _auctionIdx
    ) public whenNotPaused isExistAuction(_auctionIdx) {
        Auction storage auction = Auctions[_auctionIdx];

        require(auction.endTime <= block.timestamp, "Auction is in progress");
        require(auction.bidIdx > 0, "There is no bid history");
        require(auction.owner == msg.sender, "Not a seller");
        require(auction.complete == false, "Already settled");

        Bidding storage bidding = auction.biddings[auction.bidIdx];
        require(bidding.bidder != address(0), "There is no bid");
        bidding.withdraw = true;
        auction.complete = true;
        Deal storage deal = Deals[auction.nftCA];
        uint256 auctionFee = (auction.highestBid * deal.fee) / 1000;
        require(tokenCA.transfer(deal.feeRecipient, auctionFee));
        require(
            tokenCA.transfer(auction.owner, auction.highestBid - auctionFee)
        );
        IERC721(auction.nftCA).safeTransferFrom(
            address(this),
            bidding.bidder,
            auction.tokenId
        );

        emit WithdrawToken(
            auction.nftCA,
            auction.tokenId,
            msg.sender,
            _auctionIdx,
            auction.bidIdx,
            auction.highestBid,
            bidding.bidder
        );
    }
}
