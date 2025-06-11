// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Rental Agreement System
 * @dev Smart contract for managing rental agreements between landlords and tenants
 */
contract RentalAgreementSystem {
    
    struct RentalAgreement {
        address landlord;
        address tenant;
        uint256 monthlyRent;
        uint256 securityDeposit;
        uint256 agreementStartDate;
        uint256 agreementEndDate;
        bool isActive;
        uint256 lastPaymentDate;
        bool depositReturned;
    }
    
    mapping(uint256 => RentalAgreement) public agreements;
    mapping(address => uint256[]) public landlordAgreements;
    mapping(address => uint256[]) public tenantAgreements;
    
    uint256 public agreementCounter;
    
    event AgreementCreated(
        uint256 indexed agreementId,
        address indexed landlord,
        address indexed tenant,
        uint256 monthlyRent,
        uint256 securityDeposit
    );
    
    event RentPaid(
        uint256 indexed agreementId,
        address indexed tenant,
        uint256 amount,
        uint256 paymentDate
    );
    
    event AgreementTerminated(
        uint256 indexed agreementId,
        address indexed initiator,
        bool depositReturned
    );
    
    modifier onlyLandlord(uint256 _agreementId) {
        require(agreements[_agreementId].landlord == msg.sender, "Only landlord can perform this action");
        _;
    }
    
    modifier onlyTenant(uint256 _agreementId) {
        require(agreements[_agreementId].tenant == msg.sender, "Only tenant can perform this action");
        _;
    }
    
    modifier agreementExists(uint256 _agreementId) {
        require(_agreementId < agreementCounter, "Agreement does not exist");
        _;
    }
    
    modifier agreementActive(uint256 _agreementId) {
        require(agreements[_agreementId].isActive, "Agreement is not active");
        _;
    }
    
    /**
     * @dev Create a new rental agreement
     * @param _tenant Address of the tenant
     * @param _monthlyRent Monthly rent amount in wei
     * @param _securityDeposit Security deposit amount in wei
     * @param _durationInDays Duration of the agreement in days
     */
    function createAgreement(
        address _tenant,
        uint256 _monthlyRent,
        uint256 _securityDeposit,
        uint256 _durationInDays
    ) external payable {
        require(_tenant != address(0), "Invalid tenant address");
        require(_tenant != msg.sender, "Landlord cannot be tenant");
        require(_monthlyRent > 0, "Monthly rent must be greater than 0");
        require(_securityDeposit > 0, "Security deposit must be greater than 0");
        require(_durationInDays > 0, "Duration must be greater than 0");
        require(msg.value == _securityDeposit, "Must send exact security deposit amount");
        
        uint256 agreementId = agreementCounter++;
        
        agreements[agreementId] = RentalAgreement({
            landlord: msg.sender,
            tenant: _tenant,
            monthlyRent: _monthlyRent,
            securityDeposit: _securityDeposit,
            agreementStartDate: block.timestamp,
            agreementEndDate: block.timestamp + (_durationInDays * 1 days),
            isActive: true,
            lastPaymentDate: 0,
            depositReturned: false
        });
        
        landlordAgreements[msg.sender].push(agreementId);
        tenantAgreements[_tenant].push(agreementId);
        
        emit AgreementCreated(agreementId, msg.sender, _tenant, _monthlyRent, _securityDeposit);
    }
    
    /**
     * @dev Pay monthly rent for a specific agreement
     * @param _agreementId ID of the rental agreement
     */
    function payRent(uint256 _agreementId) 
        external 
        payable 
        agreementExists(_agreementId) 
        agreementActive(_agreementId) 
        onlyTenant(_agreementId) 
    {
        RentalAgreement storage agreement = agreements[_agreementId];
        
        require(block.timestamp <= agreement.agreementEndDate, "Agreement has expired");
        require(msg.value == agreement.monthlyRent, "Incorrect rent amount");
        
        // Check if rent is not already paid for current month
        uint256 currentMonth = (block.timestamp - agreement.agreementStartDate) / 30 days;
        uint256 lastPaymentMonth = agreement.lastPaymentDate == 0 ? 0 : 
            (agreement.lastPaymentDate - agreement.agreementStartDate) / 30 days;
        
        require(currentMonth > lastPaymentMonth, "Rent already paid for this month");
        
        agreement.lastPaymentDate = block.timestamp;
        
        // Transfer rent to landlord
        payable(agreement.landlord).transfer(msg.value);
        
        emit RentPaid(_agreementId, msg.sender, msg.value, block.timestamp);
    }
    
    /**
     * @dev Terminate rental agreement and handle security deposit
     * @param _agreementId ID of the rental agreement
     * @param _returnDeposit Whether to return the security deposit to tenant
     */
    function terminateAgreement(uint256 _agreementId, bool _returnDeposit) 
        external 
        agreementExists(_agreementId) 
        agreementActive(_agreementId) 
    {
        RentalAgreement storage agreement = agreements[_agreementId];
        
        require(
            msg.sender == agreement.landlord || msg.sender == agreement.tenant,
            "Only landlord or tenant can terminate agreement"
        );
        
        // If tenant is terminating before end date, no deposit return
        if (msg.sender == agreement.tenant && block.timestamp < agreement.agreementEndDate) {
            _returnDeposit = false;
        }
        
        agreement.isActive = false;
        
        // Handle security deposit
        if (_returnDeposit && !agreement.depositReturned) {
            agreement.depositReturned = true;
            payable(agreement.tenant).transfer(agreement.securityDeposit);
        } else if (!agreement.depositReturned) {
            // Return deposit to landlord if not returned to tenant
            agreement.depositReturned = true;
            payable(agreement.landlord).transfer(agreement.securityDeposit);
        }
        
        emit AgreementTerminated(_agreementId, msg.sender, _returnDeposit);
    }
   
    function getAgreement(uint256 _agreementId) 
        external 
        view 
        agreementExists(_agreementId) 
        returns (RentalAgreement memory) 
    {
        return agreements[_agreementId];
    }
    function getLandlordAgreements(address _landlord) external view returns (uint256[] memory) {
        return landlordAgreements[_landlord];
    }
    function getTenantAgreements(address _tenant) external view returns (uint256[] memory) {
        return tenantAgreements[_tenant];
    }

    function isRentDue(uint256 _agreementId) 
        external 
        view 
        agreementExists(_agreementId) 
        returns (bool) 
    {
        RentalAgreement memory agreement = agreements[_agreementId];
        
        if (!agreement.isActive || block.timestamp > agreement.agreementEndDate) {
            return false;
        }
        
        uint256 currentMonth = (block.timestamp - agreement.agreementStartDate) / 30 days;
        uint256 lastPaymentMonth = agreement.lastPaymentDate == 0 ? 0 : 
            (agreement.lastPaymentDate - agreement.agreementStartDate) / 30 days;
        
        return currentMonth > lastPaymentMonth;
    }
}
        uint256 currentMonth = (block.timestamp - agreement.agreementStartDate) / 30 days;
        uint256 lastPaymentMonth = agreement.lastPaymentDate == 0 ? 0 : 
            (agreement.lastPaymentDate - agreement.agreementStartDate) / 30 days;
        
        return currentMonth > lastPaymentMonth;
    }
}
