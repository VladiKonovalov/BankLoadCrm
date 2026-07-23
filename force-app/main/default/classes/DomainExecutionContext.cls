/**
 * Cross-cutting execution metadata passed through domain services.
 */
public with sharing class DomainExecutionContext {
    public enum Source {
        APEX,
        INTEGRATION,
        SYSTEM_CONTEXT
    }

    public final String correlationId;
    public final Id actorUserId;
    public final BankCrmSettings settings;
    public final Source source;

    public DomainExecutionContext(
        String correlationId,
        Id actorUserId,
        BankCrmSettings settings,
        Source source
    ) {
        this.correlationId = String.isBlank(correlationId)
            ? CorrelationIdUtil.currentOrNew()
            : correlationId;
        this.actorUserId = actorUserId;
        this.settings = settings;
        // Qualify enum type: Apex is case-insensitive, so Source.* would resolve to the source field.
        this.source = source == null
            ? DomainExecutionContext.Source.APEX
            : source;
    }

    public static DomainExecutionContext forCurrentUser(BankCrmSettings settings) {
        return new DomainExecutionContext(
            CorrelationIdUtil.currentOrNew(),
            UserInfo.getUserId(),
            settings,
            DomainExecutionContext.Source.APEX
        );
    }

    public String sourceApiValue() {
        if (this.source == DomainExecutionContext.Source.INTEGRATION) {
            return 'Integration';
        }
        if (this.source == DomainExecutionContext.Source.SYSTEM_CONTEXT) {
            return 'System';
        }
        return 'Apex';
    }
}
