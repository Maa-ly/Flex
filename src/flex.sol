//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Flex is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard {
    
    uint256 private _tokenIdCounter;
    
    // Events
    event NFTMinted(uint256 indexed tokenId, address indexed minter, string tokenURI, string quote);
    event FlexVote(uint256 indexed tokenId, address indexed voter, bool isFlex);
    event NeyVote(uint256 indexed tokenId, address indexed voter, bool isNey);
    event CommentAdded(uint256 indexed commentId, uint256 indexed tokenId, address indexed commenter, string comment);
    event DisputeCreated(uint256 indexed disputeId, uint256 indexed commentId, uint256 indexed tokenId, address indexed disputer, string reason);
    event DisputeVotingStarted(uint256 indexed disputeId, uint256 votingDeadline);
    event DisputeResolved(uint256 indexed disputeId, bool upheld, address indexed resolver);
    event NFTDeleted(uint256 indexed tokenId, address indexed deleter);
    event AuraAwarded(address indexed user, uint256 points, string activity);
    
    // Structs
    struct NFTData {
        address minter;
        string quote; // User's quote like "I look so fly"
        uint256 flexCount;
        uint256 neyCount;
        mapping(address => bool) hasFlexed;
        mapping(address => bool) hasNeyed;
        bool exists;
        bool disputed;
        uint256 disputeId;
        uint256[] commentIds; // Array of comment IDs for this NFT
    }
    
    struct UserProfile {
        uint256 totalAura;
        uint256 nftsMinted;
        uint256 flexesGiven; // How many likes they've given
        uint256 neysGiven; // How many dislikes they've given
        uint256 flexesReceived; // How many likes they've received
        uint256 neysReceived; // How many dislikes they've received
        uint256 commentsCount;
        uint256 disputesStarted;
        uint256 disputesWon;
        uint256 disputeVotesWon; // How many dispute votes they won
        mapping(string => uint256) auraBreakdown; // Points from each activity type
        uint256[] ownedNFTs; // Array of NFT IDs they own
    }
    
    struct Comment {
        uint256 tokenId;
        address commenter;
        string content;
        uint256 timestamp;
        bool disputed;
        uint256 disputeId;
    }
    
    struct Dispute {
        uint256 tokenId;
        uint256 commentId; // The comment that started the dispute
        address disputer;
        string reason;
        uint256 timestamp;
        bool resolved;
        bool upheld; // true if dispute is upheld, false if rejected
        bool votingStarted; // true when discussion phase ends and voting begins
        mapping(address => bool) hasVoted;
        uint256 votesFor; // votes to uphold dispute
        uint256 votesAgainst; // votes to reject dispute
        uint256 votingDeadline;
        uint256 discussionDeadline; // When discussion phase ends
        address[] votersFor; // Array of addresses who voted to uphold
        address[] votersAgainst; // Array of addresses who voted to reject
    }
    
    // Storage
    mapping(uint256 => NFTData) public nfts;
    mapping(uint256 => Comment) public comments;
    mapping(uint256 => Dispute) public disputes;
    mapping(address => UserProfile) public userProfiles;
    uint256 private _disputeIdCounter;
    uint256 private _commentIdCounter;
    
    // Constants
    uint256 public constant DISCUSSION_PERIOD = 3 days; // Time for comment battle/discussion
    uint256 public constant DISPUTE_VOTING_PERIOD = 7 days; // Time for voting after discussion
    uint256 public constant MIN_VOTES_FOR_RESOLUTION = 10;
    
    // Aura Points System
    uint256 public constant AURA_FLEX = 1; // Points for giving a flex (like)
    uint256 public constant AURA_NEY = 1; // Points for giving a ney (dislike)
    uint256 public constant AURA_COMMENT = 3; // Points for commenting
    uint256 public constant AURA_DISPUTE_VOTE_WIN = 5; // Points per winning dispute vote
    
    constructor() ERC721("Flex NFT", "FLEX") {}
    
    // Internal function to award aura points
    function _awardAura(address user, uint256 points, string memory activity) internal {
        UserProfile storage profile = userProfiles[user];
        profile.totalAura += points;
        profile.auraBreakdown[activity] += points;
        emit AuraAwarded(user, points, activity);
    }
    
    // Minting function - anyone can mint with a quote
    function mint(string memory tokenURI, string memory quote) public nonReentrant returns (uint256) {
        require(bytes(quote).length > 0, "Quote cannot be empty");
        
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, tokenURI);
        
        // Initialize NFT data
        NFTData storage nftData = nfts[tokenId];
        nftData.minter = msg.sender;
        nftData.quote = quote;
        nftData.exists = true;
        
        // Update user profile
        UserProfile storage profile = userProfiles[msg.sender];
        profile.nftsMinted++;
        profile.ownedNFTs.push(tokenId);
        
        emit NFTMinted(tokenId, msg.sender, tokenURI, quote);
        return tokenId;
    }
    
    // Flex (like) function
    function flex(uint256 tokenId) public {
        require(nfts[tokenId].exists, "NFT does not exist");
        require(!nfts[tokenId].hasFlexed[msg.sender], "Already flexed this NFT");
        require(!nfts[tokenId].hasNeyed[msg.sender], "Cannot flex after neying");
        
        nfts[tokenId].hasFlexed[msg.sender] = true;
        nfts[tokenId].flexCount++;
        
        // Award aura to the person giving the flex
        _awardAura(msg.sender, AURA_FLEX, "flex_given");
        
        // Update user profiles
        userProfiles[msg.sender].flexesGiven++;
        userProfiles[nfts[tokenId].minter].flexesReceived++;
        
        emit FlexVote(tokenId, msg.sender, true);
    }
    
    // Ney (dislike) function
    function ney(uint256 tokenId) public {
        require(nfts[tokenId].exists, "NFT does not exist");
        require(!nfts[tokenId].hasNeyed[msg.sender], "Already neyed this NFT");
        require(!nfts[tokenId].hasFlexed[msg.sender], "Cannot ney after flexing");
        
        nfts[tokenId].hasNeyed[msg.sender] = true;
        nfts[tokenId].neyCount++;
        
        // Award aura to the person giving the ney
        _awardAura(msg.sender, AURA_NEY, "ney_given");
        
        // Update user profiles
        userProfiles[msg.sender].neysGiven++;
        userProfiles[nfts[tokenId].minter].neysReceived++;
        
        emit NeyVote(tokenId, msg.sender, false);
    }
    
    // Add comment to NFT
    function addComment(uint256 tokenId, string memory content) public returns (uint256) {
        require(nfts[tokenId].exists, "NFT does not exist");
        require(bytes(content).length > 0, "Comment cannot be empty");
        
        uint256 commentId = _commentIdCounter;
        _commentIdCounter++;
        
        Comment storage comment = comments[commentId];
        comment.tokenId = tokenId;
        comment.commenter = msg.sender;
        comment.content = content;
        comment.timestamp = block.timestamp;
        
        // Add comment ID to NFT's comment list
        nfts[tokenId].commentIds.push(commentId);
        
        // Award aura and update profile
        _awardAura(msg.sender, AURA_COMMENT, "comment");
        userProfiles[msg.sender].commentsCount++;
        
        emit CommentAdded(commentId, tokenId, msg.sender, content);
        return commentId;
    }
    
    // Create dispute from a comment (like disagreeing with a quote in the post)
    function createDispute(uint256 commentId, string memory reason) public returns (uint256) {
        require(comments[commentId].commenter != address(0), "Comment does not exist");
        require(!comments[commentId].disputed, "Comment already disputed");
        require(bytes(reason).length > 0, "Dispute reason required");
        
        uint256 tokenId = comments[commentId].tokenId;
        require(nfts[tokenId].exists, "NFT does not exist");
        require(!nfts[tokenId].disputed, "NFT already disputed");
        
        uint256 disputeId = _disputeIdCounter;
        _disputeIdCounter++;
        
        Dispute storage dispute = disputes[disputeId];
        dispute.tokenId = tokenId;
        dispute.commentId = commentId;
        dispute.disputer = msg.sender;
        dispute.reason = reason;
        dispute.timestamp = block.timestamp;
        dispute.discussionDeadline = block.timestamp + DISCUSSION_PERIOD;
        dispute.votingDeadline = block.timestamp + DISCUSSION_PERIOD + DISPUTE_VOTING_PERIOD;
        
        // Mark comment and NFT as disputed
        comments[commentId].disputed = true;
        comments[commentId].disputeId = disputeId;
        nfts[tokenId].disputed = true;
        nfts[tokenId].disputeId = disputeId;
        
        // Update disputer's profile
        userProfiles[msg.sender].disputesStarted++;
        
        emit DisputeCreated(disputeId, commentId, tokenId, msg.sender, reason);
        return disputeId;
    }
    
    // Start voting phase (can be called after discussion period ends)
    function startVoting(uint256 disputeId) public {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.disputer != address(0), "Dispute does not exist");
        require(!dispute.resolved, "Dispute already resolved");
        require(!dispute.votingStarted, "Voting already started");
        require(block.timestamp > dispute.discussionDeadline, "Discussion period not ended");
        
        dispute.votingStarted = true;
        emit DisputeVotingStarted(disputeId, dispute.votingDeadline);
    }
    
    // Vote on dispute resolution (only after voting has started)
    function voteOnDispute(uint256 disputeId, bool voteToUphold) public {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.disputer != address(0), "Dispute does not exist");
        require(!dispute.resolved, "Dispute already resolved");
        require(dispute.votingStarted, "Voting not started yet");
        require(block.timestamp <= dispute.votingDeadline, "Voting period ended");
        require(!dispute.hasVoted[msg.sender], "Already voted on this dispute");
        
        dispute.hasVoted[msg.sender] = true;
        
        if (voteToUphold) {
            dispute.votesFor++;
            dispute.votersFor.push(msg.sender);
        } else {
            dispute.votesAgainst++;
            dispute.votersAgainst.push(msg.sender);
        }
    }
    
    // Resolve dispute (can be called by anyone after voting period)
    function resolveDispute(uint256 disputeId) public {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.disputer != address(0), "Dispute does not exist");
        require(!dispute.resolved, "Dispute already resolved");
        require(dispute.votingStarted, "Voting not started");
        require(block.timestamp > dispute.votingDeadline, "Voting period not ended");
        
        uint256 totalVotes = dispute.votesFor + dispute.votesAgainst;
        require(totalVotes >= MIN_VOTES_FOR_RESOLUTION, "Not enough votes for resolution");
        
        dispute.resolved = true;
        dispute.upheld = dispute.votesFor > dispute.votesAgainst;
        
        uint256 tokenId = dispute.tokenId;
        uint256 commentId = dispute.commentId;
        
        // Award aura to winning voters and update profiles
        address[] memory winners = dispute.upheld ? dispute.votersFor : dispute.votersAgainst;
        for (uint256 i = 0; i < winners.length; i++) {
            _awardAura(winners[i], AURA_DISPUTE_VOTE_WIN, "dispute_vote_win");
            userProfiles[winners[i]].disputeVotesWon++;
        }
        
        // If disputer won (dispute upheld), update their wins
        if (dispute.upheld) {
            userProfiles[dispute.disputer].disputesWon++;
        }
        
        // Clear dispute status
        nfts[tokenId].disputed = false;
        comments[commentId].disputed = false;
        
        // If dispute is upheld, delete the NFT
        if (dispute.upheld) {
            _deleteNFT(tokenId);
        }
        
        emit DisputeResolved(disputeId, dispute.upheld, msg.sender);
    }
    
    // Delete NFT (internal function called when dispute is upheld)
    function _deleteNFT(uint256 tokenId) internal {
        require(nfts[tokenId].exists, "NFT does not exist");
        
        address owner = ownerOf(tokenId);
        
        // Remove NFT from user's owned NFTs array
        uint256[] storage ownedNFTs = userProfiles[owner].ownedNFTs;
        for (uint256 i = 0; i < ownedNFTs.length; i++) {
            if (ownedNFTs[i] == tokenId) {
                ownedNFTs[i] = ownedNFTs[ownedNFTs.length - 1];
                ownedNFTs.pop();
                break;
            }
        }
        
        // Burn the token
        _burn(tokenId);
        
        // Clear NFT data
        delete nfts[tokenId];
        
        emit NFTDeleted(tokenId, msg.sender);
    }
    
    // Allow NFT minter to delete their own NFT
    function deleteMyNFT(uint256 tokenId) public {
        require(nfts[tokenId].exists, "NFT does not exist");
        require(nfts[tokenId].minter == msg.sender, "Only minter can delete");
        require(!nfts[tokenId].disputed, "Cannot delete disputed NFT");
        
        _deleteNFT(tokenId);
    }
    
    // View functions
    function getNFTData(uint256 tokenId) public view returns (
        address minter,
        string memory quote,
        uint256 flexCount,
        uint256 neyCount,
        bool exists,
        bool disputed,
        uint256 disputeId
    ) {
        NFTData storage nft = nfts[tokenId];
        return (
            nft.minter,
            nft.quote,
            nft.flexCount,
            nft.neyCount,
            nft.exists,
            nft.disputed,
            nft.disputeId
        );
    }
    
    function getDisputeData(uint256 disputeId) public view returns (
        uint256 tokenId,
        uint256 commentId,
        address disputer,
        string memory reason,
        uint256 timestamp,
        bool resolved,
        bool upheld,
        bool votingStarted,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 discussionDeadline,
        uint256 votingDeadline
    ) {
        Dispute storage dispute = disputes[disputeId];
        return (
            dispute.tokenId,
            dispute.commentId,
            dispute.disputer,
            dispute.reason,
            dispute.timestamp,
            dispute.resolved,
            dispute.upheld,
            dispute.votingStarted,
            dispute.votesFor,
            dispute.votesAgainst,
            dispute.discussionDeadline,
            dispute.votingDeadline
        );
    }
    
    function getCommentData(uint256 commentId) public view returns (
        uint256 tokenId,
        address commenter,
        string memory content,
        uint256 timestamp,
        bool disputed,
        uint256 disputeId
    ) {
        Comment storage comment = comments[commentId];
        return (
            comment.tokenId,
            comment.commenter,
            comment.content,
            comment.timestamp,
            comment.disputed,
            comment.disputeId
        );
    }
    
    function getNFTComments(uint256 tokenId) public view returns (uint256[] memory) {
        require(nfts[tokenId].exists, "NFT does not exist");
        return nfts[tokenId].commentIds;
    }
    
    // User Profile Functions
    function getUserProfile(address user) public view returns (
        uint256 totalAura,
        uint256 nftsMinted,
        uint256 flexesGiven,
        uint256 neysGiven,
        uint256 flexesReceived,
        uint256 neysReceived,
        uint256 commentsCount,
        uint256 disputesStarted,
        uint256 disputesWon,
        uint256 disputeVotesWon
    ) {
        UserProfile storage profile = userProfiles[user];
        return (
            profile.totalAura,
            profile.nftsMinted,
            profile.flexesGiven,
            profile.neysGiven,
            profile.flexesReceived,
            profile.neysReceived,
            profile.commentsCount,
            profile.disputesStarted,
            profile.disputesWon,
            profile.disputeVotesWon
        );
    }
    
    function getUserAuraFromActivity(address user, string memory activity) public view returns (uint256) {
        return userProfiles[user].auraBreakdown[activity];
    }
    
    function getUserOwnedNFTs(address user) public view returns (uint256[] memory) {
        return userProfiles[user].ownedNFTs;
    }
    
    // Get detailed aura breakdown for a user
    function getUserAuraBreakdown(address user) public view returns (
        uint256 fromFlexGiven,
        uint256 fromNeyGiven,
        uint256 fromComments,
        uint256 fromDisputeVoteWins
    ) {
        UserProfile storage profile = userProfiles[user];
        return (
            profile.auraBreakdown["flex_given"],
            profile.auraBreakdown["ney_given"],
            profile.auraBreakdown["comment"],
            profile.auraBreakdown["dispute_vote_win"]
        );
    }
    
    function hasUserFlexed(uint256 tokenId, address user) public view returns (bool) {
        return nfts[tokenId].hasFlexed[user];
    }
    
    function hasUserNeyed(uint256 tokenId, address user) public view returns (bool) {
        return nfts[tokenId].hasNeyed[user];
    }
    
    function hasUserVotedOnDispute(uint256 disputeId, address user) public view returns (bool) {
        return disputes[disputeId].hasVoted[user];
    }
    
    function getTotalNFTs() public view returns (uint256) {
        return _tokenIdCounter;
    }
    
    function getTotalComments() public view returns (uint256) {
        return _commentIdCounter;
    }
    
    function getTotalDisputes() public view returns (uint256) {
        return _disputeIdCounter;
    }
    
    // Required overrides
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }
    
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}